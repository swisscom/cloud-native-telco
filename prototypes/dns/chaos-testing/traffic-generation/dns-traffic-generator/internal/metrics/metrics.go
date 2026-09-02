// Package metrics defines the Prometheus metrics and the HTTP server that exposes them.
package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Values of the `result` label on LookupTotal, describing how a resolution
// compared to the answer the generator intended for that host.
const (
	// ResultMatch means the resolution returned exactly the intended answer.
	ResultMatch = "match"
	// ResultMismatch means it did not: a different address, an unexpected
	// NXDOMAIN, a SERVFAIL, or no answer at all.
	ResultMismatch = "mismatch"
	// ResultUntracked means the generator holds no intent for the host, so the
	// resolution cannot be judged. Excluded from the accuracy ratio.
	ResultUntracked = "untracked"
)

// Metrics exposed on /metrics.
var (
	// LookupTotal counts DNS lookups by host, server, response code and whether
	// the answer matched the generator's intent.
	LookupTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "dns_traffic_lookups_total",
			Help: "Total DNS lookups performed.",
		},
		[]string{"host", "dns_server", "rcode", "result"},
	)

	// LookupErrors counts failed DNS exchanges by host, server and reason.
	LookupErrors = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "dns_traffic_lookup_errors_total",
			Help: "Total DNS lookup errors.",
		},
		[]string{"host", "dns_server", "reason"},
	)

	// LookupDuration tracks DNS lookup latency.
	LookupDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "dns_traffic_lookup_duration_seconds",
			Help:    "DNS lookup latency.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"host", "dns_server", "rcode"},
	)

	// RecordUpdates counts DNSEndpoint patch attempts by result. It is deliberately
	// not labelled per record: that split the rate across one sparse series per
	// record, and rate() cannot see the first increment of a series, so the rotation
	// rate under-reported for minutes after every restart.
	RecordUpdates = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "dns_traffic_record_updates_total",
			Help: "Total DNS record update attempts.",
		},
		[]string{"result"},
	)
)
