package updater

import (
	"net"
	"testing"
)

func newTestUpdater(t *testing.T, cidr string) *Updater {
	t.Helper()

	_, subnet, err := net.ParseCIDR(cidr)
	if err != nil {
		t.Fatalf("parsing %s: %v", cidr, err)
	}

	ones, bits := subnet.Mask.Size()

	u := &Updater{size: 1 << uint(bits-ones)}
	u.base = uint32(subnet.IP.To4()[0])<<24 |
		uint32(subnet.IP.To4()[1])<<16 |
		uint32(subnet.IP.To4()[2])<<8 |
		uint32(subnet.IP.To4()[3])

	return u
}

func TestPickAddressStaysInSubnetAndAlwaysChanges(t *testing.T) {
	u := newTestUpdater(t, "11.1.1.192/27")
	_, subnet, _ := net.ParseCIDR("11.1.1.192/27")

	current := "11.1.1.200"

	for i := 0; i < 500; i++ {
		next := u.pickAddress(current)

		if next == current {
			t.Fatalf("rotation returned the current address %s, which would be invisible", next)
		}

		if !subnet.Contains(net.ParseIP(next)) {
			t.Fatalf("address %s is outside %s", next, subnet)
		}

		current = next
	}
}

func TestAddressAtCoversTheWholeSubnet(t *testing.T) {
	u := newTestUpdater(t, "10.1.1.192/27")

	if got := u.addressAt(0); got != "10.1.1.192" {
		t.Fatalf("expected first address 10.1.1.192, got %s", got)
	}

	if got := u.addressAt(u.size - 1); got != "10.1.1.223" {
		t.Fatalf("expected last address 10.1.1.223, got %s", got)
	}
}

func TestEndpointSpecCarriesASingleARecord(t *testing.T) {
	spec := endpointSpec("chaos-test-1-berne.5gc.3gppnetwork.org", "11.1.1.200")

	endpoints, ok := spec["endpoints"].([]map[string]interface{})
	if !ok || len(endpoints) != 1 {
		t.Fatalf("expected exactly one endpoint, got %v", spec["endpoints"])
	}

	if endpoints[0]["recordType"] != "A" {
		t.Errorf("expected an A record, got %v", endpoints[0]["recordType"])
	}

	if endpoints[0]["dnsName"] != "chaos-test-1-berne.5gc.3gppnetwork.org" {
		t.Errorf("unexpected dnsName %v", endpoints[0]["dnsName"])
	}

	targets, ok := endpoints[0]["targets"].([]string)
	if !ok || len(targets) != 1 || targets[0] != "11.1.1.200" {
		t.Errorf("unexpected targets %v", endpoints[0]["targets"])
	}
}
