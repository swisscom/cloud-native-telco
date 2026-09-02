// Package intent tracks the DNS answer the generator itself has provisioned for
// every host it queries.
//
// The generator is the only writer of the DNSEndpoint resources backing these
// hosts, and it only ever queries records served by its own cluster, so this
// map is the authoritative expectation a resolution is judged against.
package intent

import "sync"

// NXDOMAIN is the intent recorded for hosts that are expected not to resolve.
const NXDOMAIN = ""

// Store holds the intended A record for every tracked host.
type Store struct {
	mu        sync.RWMutex
	intents   map[string]string
	rotatable []string
}

// New returns an empty Store.
func New() *Store {
	return &Store{intents: make(map[string]string)}
}

// Seed records the initial intent for a host. Hosts seeded with an address are
// rotatable; hosts seeded as NXDOMAIN are not, since they have no record to patch.
func (s *Store) Seed(host, address string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.intents[host]; exists {
		return
	}

	s.intents[host] = address

	if address != NXDOMAIN {
		s.rotatable = append(s.rotatable, host)
	}
}

// Set updates the intended address for a host after a successful patch.
func (s *Store) Set(host, address string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.intents[host] = address
}

// Get returns the intended address for a host, and whether the host is tracked.
func (s *Store) Get(host string) (string, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	address, ok := s.intents[host]

	return address, ok
}

// Rotatable returns the hosts that are backed by a DNSEndpoint.
func (s *Store) Rotatable() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]string, len(s.rotatable))
	copy(out, s.rotatable)

	return out
}
