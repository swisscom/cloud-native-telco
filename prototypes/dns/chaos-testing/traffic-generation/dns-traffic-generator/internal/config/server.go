package config

import (
	"fmt"
	"strings"
)

const defaultDNSPort = "53"

// Server describes the protocol and address used to reach a DNS server.
type Server struct {
	Network string
	Address string
	Name    string
}

func (s Server) String() string {
	return s.Name
}

// ParseServers converts a comma-separated list such as
// "udp://8.8.8.8:53,tcp://1.1.1.1" into Server values.
// The protocol defaults to udp and the port defaults to 53.
func ParseServers(raw string) ([]Server, error) {
	items := SplitCSV(raw)
	if len(items) == 0 {
		return nil, fmt.Errorf("dns-servers cannot be empty")
	}

	out := make([]Server, 0, len(items))

	for _, item := range items {
		server, err := parseServer(item)
		if err != nil {
			return nil, err
		}

		out = append(out, server)
	}

	return out, nil
}

func parseServer(item string) (Server, error) {
	network := "udp"
	address := item

	parts := strings.Split(item, "://")

	switch len(parts) {
	case 1:
		address = strings.TrimSpace(parts[0])
	case 2:
		network = strings.ToLower(strings.TrimSpace(parts[0]))
		address = strings.TrimSpace(parts[1])
	default:
		return Server{}, fmt.Errorf("invalid dns server format: %s", item)
	}

	if network != "udp" && network != "tcp" {
		return Server{}, fmt.Errorf("unsupported dns network %q for %s", network, item)
	}

	if address == "" {
		return Server{}, fmt.Errorf("missing dns server address in %q", item)
	}

	if !strings.Contains(address, ":") {
		address += ":" + defaultDNSPort
	}

	return Server{
		Network: network,
		Address: address,
		Name:    fmt.Sprintf("%s://%s", network, address),
	}, nil
}
