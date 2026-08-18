// Command dns-traffic-generator generates DNS traffic, optionally rotates
// DNSEndpoint records, and exposes Prometheus metrics.
package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"github.com/taadage2/dns-traffic-generator/internal/config"
	"github.com/taadage2/dns-traffic-generator/internal/intent"
	"github.com/taadage2/dns-traffic-generator/internal/metrics"
	"github.com/taadage2/dns-traffic-generator/internal/traffic"
	"github.com/taadage2/dns-traffic-generator/internal/updater"
	"github.com/taadage2/dns-traffic-generator/internal/zone"
)

func main() {
	cfg, err := config.Parse()
	if err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	// 3. Expose metrics for scraping.
	metricsServer := metrics.StartServer(cfg.Listen)

	var wg sync.WaitGroup

	// The answers this generator expects to see. Populated before any traffic
	// starts so no lookup is judged blind.
	store := intent.New()

	// 2. Create the records this generator owns, then keep rotating them.
	names := zone.Expand(cfg.Domain, cfg.RecordCount, cfg.NegativeCount)

	u, err := updater.New(cfg, store)
	if err != nil {
		log.Fatalf("failed to initialize DNS updater: %v", err)
	}

	if err := u.Populate(ctx, names); err != nil {
		log.Fatalf("failed to populate DNS records: %v", err)
	}

	if cfg.EnableRotation {
		wg.Add(1)

		go func() {
			defer wg.Done()
			u.Run(ctx)
		}()
	}

	// 1. Generate DNS traffic towards the predefined instances.
	traffic.Start(ctx, &wg, cfg, names.All(), store)

	<-ctx.Done()
	log.Printf("shutdown requested")

	metrics.StopServer(metricsServer)
	wg.Wait()

	log.Printf("shutdown complete")
}
