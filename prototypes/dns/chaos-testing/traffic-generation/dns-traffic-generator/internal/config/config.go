// Package config parses and validates runtime settings for the traffic generator.
package config

import (
	"flag"
	"fmt"
	"net"
	"strings"
	"time"
)

// Config holds every runtime setting for the generator.
type Config struct {
	// Metrics
	Listen string

	// Traffic generation
	Interval   time.Duration
	Timeout    time.Duration
	DNSServers []Server

	// Records owned by this generator
	Domain        string
	RecordCount   int
	NegativeCount int

	// DNS record updates
	EnableRotation  bool
	UpdateInterval  time.Duration
	UpdateNamespace string
	Subnet          *net.IPNet
}

// Parse reads command line flags and returns a validated Config.
func Parse() (Config, error) {
	var (
		listen          = flag.String("listen", ":9090", "address for metrics endpoint")
		interval        = flag.Duration("interval", 5*time.Second, "interval between DNS lookups")
		timeout         = flag.Duration("timeout", 3*time.Second, "timeout for each DNS lookup")
		dnsServers      = flag.String("dns-servers", "udp://8.8.8.8:53,udp://1.1.1.1:53", "comma-separated DNS servers")
		domain          = flag.String("domain", "", "domain this generator populates and queries")
		recordCount     = flag.Int("record-count", 50, "number of records to create and watch in the domain")
		negativeCount   = flag.Int("negative-count", 1, "number of names that are never created and must return NXDOMAIN")
		enableRotation  = flag.Bool("enable-rotation", true, "keep rotating the target of the created records")
		updateInterval  = flag.Duration("update-interval", 20*time.Second, "interval between DNS record updates")
		updateNamespace = flag.String("update-namespace", "default", "namespace holding the DNSEndpoint resources")
		subnetCIDR      = flag.String("subnet", "", "IPv4 CIDR the record targets are drawn from")
	)

	flag.Parse()

	servers, err := ParseServers(*dnsServers)
	if err != nil {
		return Config{}, err
	}

	subnet, err := parseSubnet(*subnetCIDR)
	if err != nil {
		return Config{}, err
	}

	cfg := Config{
		Listen:          *listen,
		Interval:        *interval,
		Timeout:         *timeout,
		DNSServers:      servers,
		Domain:          strings.TrimSpace(*domain),
		RecordCount:     *recordCount,
		NegativeCount:   *negativeCount,
		EnableRotation:  *enableRotation,
		UpdateInterval:  *updateInterval,
		UpdateNamespace: *updateNamespace,
		Subnet:          subnet,
	}

	if err := cfg.Validate(); err != nil {
		return Config{}, err
	}

	return cfg, nil
}

// parseSubnet accepts an empty value, which leaves the subnet unconfigured.
func parseSubnet(raw string) (*net.IPNet, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}

	_, subnet, err := net.ParseCIDR(raw)
	if err != nil {
		return nil, fmt.Errorf("invalid subnet %q: %w", raw, err)
	}

	if subnet.IP.To4() == nil {
		return nil, fmt.Errorf("subnet must be IPv4: %s", raw)
	}

	return subnet, nil
}

// Validate checks that the configuration is internally consistent.
func (c Config) Validate() error {
	if c.Domain == "" {
		return fmt.Errorf("domain cannot be empty")
	}

	if c.RecordCount < 1 {
		return fmt.Errorf("record-count must be at least one")
	}

	if c.NegativeCount < 0 {
		return fmt.Errorf("negative-count cannot be negative")
	}

	if c.Interval <= 0 {
		return fmt.Errorf("interval must be greater than zero")
	}

	if c.Timeout <= 0 {
		return fmt.Errorf("timeout must be greater than zero")
	}

	// The subnet is not rotation-only: the initial target of every created record
	// is drawn from it as well, so it is required even when rotation is off.
	if c.Subnet == nil {
		return fmt.Errorf("subnet is required")
	}

	if ones, bits := c.Subnet.Mask.Size(); bits-ones < 1 {
		return fmt.Errorf("subnet must contain at least two addresses: %s", c.Subnet)
	}

	if c.EnableRotation && c.UpdateInterval <= 0 {
		return fmt.Errorf("update-interval must be greater than zero")
	}

	return nil
}

// SplitCSV splits a comma-separated string, trimming spaces and dropping empties.
func SplitCSV(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))

	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}

	return out
}
