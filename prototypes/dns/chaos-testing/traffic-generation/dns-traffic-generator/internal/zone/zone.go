// Package zone derives the record names a generator owns inside a domain.
//
// The generator is handed a domain and told how many records to populate, so the
// names are computed rather than configured. The shared prefix and the domain
// suffix together mark ownership, which is what makes it safe to delete records
// the generator no longer wants without touching anything else in the namespace.
package zone

import (
	"fmt"
	"strings"
)

// Prefix marks every record this generator provisions.
const Prefix = "chaos-test-"

// absentInfix distinguishes names that are deliberately never created.
const absentInfix = "absent-"

// Names holds the record names derived for one domain.
type Names struct {
	// Positive names are backed by a DNSEndpoint and expected to resolve.
	Positive []string
	// Negative names are never created and are expected to return NXDOMAIN.
	Negative []string
}

// All returns every name the generator queries, positives first.
func (n Names) All() []string {
	out := make([]string, 0, len(n.Positive)+len(n.Negative))
	out = append(out, n.Positive...)

	return append(out, n.Negative...)
}

// Expand builds the record names for a domain.
func Expand(domain string, records, negatives int) Names {
	names := Names{
		Positive: make([]string, 0, records),
		Negative: make([]string, 0, negatives),
	}

	for i := 1; i <= records; i++ {
		names.Positive = append(names.Positive, fmt.Sprintf("%s%d-%s", Prefix, i, domain))
	}

	for i := 1; i <= negatives; i++ {
		names.Negative = append(names.Negative, fmt.Sprintf("%s%s%d-%s", Prefix, absentInfix, i, domain))
	}

	return names
}

// Owns reports whether a record name was provisioned by a generator for this
// domain. Both halves matter: the prefix scopes deletion to generator-owned
// records, the suffix scopes it to this cluster's domain.
func Owns(name, domain string) bool {
	return strings.HasPrefix(name, Prefix) && strings.HasSuffix(name, "-"+domain)
}
