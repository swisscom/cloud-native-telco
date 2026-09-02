// Package updater provisions the ExternalDNS DNSEndpoint resources this
// generator owns and rotates their target IPs.
package updater

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"

	"github.com/taadage2/dns-traffic-generator/internal/config"
	"github.com/taadage2/dns-traffic-generator/internal/intent"
	"github.com/taadage2/dns-traffic-generator/internal/kube"
	"github.com/taadage2/dns-traffic-generator/internal/metrics"
	"github.com/taadage2/dns-traffic-generator/internal/zone"
)

// dnsEndpointGVR points at the ExternalDNS DNSEndpoint custom resource.
var dnsEndpointGVR = schema.GroupVersionResource{
	Group:    "externaldns.k8s.io",
	Version:  "v1alpha1",
	Resource: "dnsendpoints",
}

// fieldManager owns the fields this generator applies, so a restart re-applies
// its own records instead of conflicting with what the previous run left behind.
const fieldManager = "dns-traffic-generator"

// Updater creates the DNSEndpoint resources for a domain, rotates their target
// IP on an interval, and keeps the intent store in step with what it provisioned.
type Updater struct {
	dyn       dynamic.Interface
	store     *intent.Store
	namespace string
	domain    string
	interval  time.Duration
	base      uint32
	size      uint32
}

// New builds an Updater using in-cluster or local Kubernetes credentials.
func New(cfg config.Config, store *intent.Store) (*Updater, error) {
	restCfg, err := kube.RESTConfig()
	if err != nil {
		return nil, err
	}

	dyn, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return nil, fmt.Errorf("creating dynamic client: %w", err)
	}

	ones, bits := cfg.Subnet.Mask.Size()

	return &Updater{
		dyn:       dyn,
		store:     store,
		namespace: cfg.UpdateNamespace,
		domain:    cfg.Domain,
		interval:  cfg.UpdateInterval,
		base:      binary.BigEndian.Uint32(cfg.Subnet.IP.To4()),
		size:      1 << uint(bits-ones),
	}, nil
}

// Populate creates a DNSEndpoint for every positive name and records the address
// it wrote as the initial intent. Negative names get no resource at all, which is
// what makes their expected NXDOMAIN meaningful.
func (u *Updater) Populate(ctx context.Context, names zone.Names) error {
	for _, name := range names.Positive {
		target := u.pickAddress("")

		if err := u.applyEndpoint(ctx, name, target); err != nil {
			return err
		}

		u.store.Seed(name, target)
	}

	for _, name := range names.Negative {
		u.store.Seed(name, intent.NXDOMAIN)
	}

	log.Printf("records populated namespace=%s domain=%s records=%d nxdomain=%d",
		u.namespace, u.domain, len(names.Positive), len(names.Negative))

	return u.reconcile(ctx, names)
}

// reconcile deletes records this generator owns that are no longer wanted, so
// lowering the record count does not leave names resolving forever.
func (u *Updater) reconcile(ctx context.Context, names zone.Names) error {
	list, err := u.dyn.Resource(dnsEndpointGVR).Namespace(u.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("listing dnsendpoints in %s: %w", u.namespace, err)
	}

	wanted := make(map[string]struct{}, len(names.Positive))
	for _, name := range names.Positive {
		wanted[name] = struct{}{}
	}

	var removed int

	for i := range list.Items {
		name := list.Items[i].GetName()

		if !zone.Owns(name, u.domain) {
			continue
		}

		if _, keep := wanted[name]; keep {
			continue
		}

		err := u.dyn.Resource(dnsEndpointGVR).Namespace(u.namespace).Delete(ctx, name, metav1.DeleteOptions{})
		if err != nil {
			return fmt.Errorf("deleting orphaned dnsendpoint %s: %w", name, err)
		}

		removed++
	}

	if removed > 0 {
		log.Printf("orphaned records removed namespace=%s domain=%s count=%d", u.namespace, u.domain, removed)
	}

	return nil
}

// Run patches one randomly chosen DNSEndpoint on each tick until the context is cancelled.
func (u *Updater) Run(ctx context.Context) {
	ticker := time.NewTicker(u.interval)
	defer ticker.Stop()

	log.Printf("dns updater running namespace=%s rotatable=%d", u.namespace, len(u.store.Rotatable()))

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			u.rotateOnce(ctx)
		}
	}
}

func (u *Updater) rotateOnce(ctx context.Context) {
	hosts := u.store.Rotatable()
	if len(hosts) == 0 {
		return
	}

	host := hosts[rand.Intn(len(hosts))]

	current, _ := u.store.Get(host)
	target := u.pickAddress(current)

	if err := u.patchEndpoint(ctx, host, target); err != nil {
		metrics.RecordUpdates.WithLabelValues("error").Inc()
		log.Printf("dns update failed dnsendpoint=%s target=%s error=%v", host, target, err)

		return
	}

	// Only now is the new address the intended answer; a failed patch leaves the
	// previous intent in place.
	u.store.Set(host, target)
	metrics.RecordUpdates.WithLabelValues("success").Inc()
	log.Printf("dns updated dnsendpoint=%s target=%s", host, target)
}

// pickAddress returns a random address from the rotation subnet, never the one
// currently intended, so every rotation is an observable change.
func (u *Updater) pickAddress(exclude string) string {
	offset := uint32(rand.Int31n(int32(u.size)))

	address := u.addressAt(offset)
	if address == exclude {
		address = u.addressAt((offset + 1) % u.size)
	}

	return address
}

func (u *Updater) addressAt(offset uint32) string {
	buf := make([]byte, net.IPv4len)
	binary.BigEndian.PutUint32(buf, u.base+offset)

	return net.IP(buf).String()
}

// applyEndpoint server-side applies a DNSEndpoint carrying a single A record.
func (u *Updater) applyEndpoint(ctx context.Context, name, target string) error {
	object := map[string]interface{}{
		"apiVersion": dnsEndpointGVR.Group + "/" + dnsEndpointGVR.Version,
		"kind":       "DNSEndpoint",
		"metadata": map[string]interface{}{
			"name":      name,
			"namespace": u.namespace,
		},
		"spec": endpointSpec(name, target),
	}

	body, err := json.Marshal(object)
	if err != nil {
		return fmt.Errorf("marshaling dnsendpoint %s: %w", name, err)
	}

	_, err = u.dyn.Resource(dnsEndpointGVR).Namespace(u.namespace).Patch(
		ctx,
		name,
		types.ApplyPatchType,
		body,
		metav1.PatchOptions{FieldManager: fieldManager, Force: ptr(true)},
	)
	if err != nil {
		return fmt.Errorf("applying dnsendpoint %s: %w", name, err)
	}

	return nil
}

// patchEndpoint applies a merge patch setting a single A record for the resource.
func (u *Updater) patchEndpoint(ctx context.Context, name, target string) error {
	body, err := json.Marshal(map[string]interface{}{"spec": endpointSpec(name, target)})
	if err != nil {
		return fmt.Errorf("marshaling patch: %w", err)
	}

	_, err = u.dyn.Resource(dnsEndpointGVR).Namespace(u.namespace).Patch(
		ctx,
		name,
		types.MergePatchType,
		body,
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("patching dnsendpoint %s: %w", name, err)
	}

	return nil
}

// endpointSpec builds the DNSEndpoint spec for a single A record.
func endpointSpec(name, target string) map[string]interface{} {
	return map[string]interface{}{
		"endpoints": []map[string]interface{}{
			{
				"dnsName":    name,
				"recordType": "A",
				"targets":    []string{target},
			},
		},
	}
}

func ptr[T any](v T) *T {
	return &v
}
