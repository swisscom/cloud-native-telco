// Package traffic generates continuous DNS query load against configured servers.
package traffic

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/miekg/dns"

	"github.com/taadage2/dns-traffic-generator/internal/config"
	"github.com/taadage2/dns-traffic-generator/internal/intent"
	"github.com/taadage2/dns-traffic-generator/internal/metrics"
)

// rcodeExchangeError labels lookups that never received a response at all.
const rcodeExchangeError = "ERROR"

// noRcode marks the absence of a response when classifying a failed exchange.
const noRcode = -1

// Generator repeatedly queries a single host against a single DNS server.
type Generator struct {
	host     string
	server   config.Server
	interval time.Duration
	client   *dns.Client
	intent   *intent.Store
}

// NewGenerator builds a Generator for one host/server pair.
func NewGenerator(host string, server config.Server, interval, timeout time.Duration, store *intent.Store) *Generator {
	return &Generator{
		host:     host,
		server:   server,
		interval: interval,
		client:   &dns.Client{Net: server.Network, Timeout: timeout},
		intent:   store,
	}
}

// Run performs lookups on a fixed interval until the context is cancelled.
func (g *Generator) Run(ctx context.Context) {
	ticker := time.NewTicker(g.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			g.lookup(ctx)
		}
	}
}

// lookup issues one A query and records the outcome as metrics.
func (g *Generator) lookup(ctx context.Context) {
	msg := new(dns.Msg)
	msg.SetQuestion(dns.Fqdn(g.host), dns.TypeA)

	start := time.Now()

	resp, _, err := g.client.ExchangeContext(ctx, msg, g.server.Address)
	if err != nil {
		metrics.LookupErrors.WithLabelValues(g.host, g.server.Name, "exchange_error").Inc()
		// A query that never came back is still a resolution that did not yield the
		// intended answer, so it has to reach the accuracy ratio. Leaving it out is
		// what previously made the metric go blank during an outage.
		metrics.LookupTotal.
			WithLabelValues(g.host, g.server.Name, rcodeExchangeError, g.classify(nil, noRcode)).
			Inc()
		log.Printf("lookup failed host=%s server=%s error=%v", g.host, g.server.Name, err)

		return
	}

	rcode := rcodeString(resp.Rcode)
	result := g.classify(answerAddresses(resp), resp.Rcode)

	metrics.LookupTotal.WithLabelValues(g.host, g.server.Name, rcode, result).Inc()
	metrics.LookupDuration.WithLabelValues(g.host, g.server.Name, rcode).Observe(time.Since(start).Seconds())
}

// classify compares a resolution against the answer the generator intends for
// this host. Anything that is not exactly the intended answer is a mismatch.
func (g *Generator) classify(resolved []string, rcode int) string {
	intended, tracked := g.intent.Get(g.host)
	if !tracked {
		return metrics.ResultUntracked
	}

	if intended == intent.NXDOMAIN {
		if rcode == dns.RcodeNameError {
			return metrics.ResultMatch
		}

		return metrics.ResultMismatch
	}

	if rcode != dns.RcodeSuccess {
		return metrics.ResultMismatch
	}

	if len(resolved) == 1 && resolved[0] == intended {
		return metrics.ResultMatch
	}

	return metrics.ResultMismatch
}

// answerAddresses returns the A record addresses carried in the answer section.
func answerAddresses(msg *dns.Msg) []string {
	out := make([]string, 0, len(msg.Answer))

	for _, rr := range msg.Answer {
		if a, ok := rr.(*dns.A); ok {
			out = append(out, a.A.String())
		}
	}

	return out
}

func rcodeString(rcode int) string {
	if s, ok := dns.RcodeToString[rcode]; ok {
		return s
	}

	return fmt.Sprintf("RCODE_%d", rcode)
}

// Start launches one Generator per host/server combination.
func Start(ctx context.Context, wg *sync.WaitGroup, cfg config.Config, hosts []string, store *intent.Store) {
	for _, host := range hosts {
		for _, server := range cfg.DNSServers {
			generator := NewGenerator(host, server, cfg.Interval, cfg.Timeout, store)

			wg.Add(1)

			go func() {
				defer wg.Done()
				generator.Run(ctx)
			}()
		}
	}

	log.Printf("traffic generation started hosts=%d servers=%v interval=%s", len(hosts), cfg.DNSServers, cfg.Interval)
}
