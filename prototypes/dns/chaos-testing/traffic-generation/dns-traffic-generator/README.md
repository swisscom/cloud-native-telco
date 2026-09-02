# dns-traffic-generator

`dns-traffic-generator` is a small Go service inspired by the `hostlookuper` project.
It combines three capabilities in one binary:

1. Create the DNS records (DNSEndpoint CRDs) it is going to query.
2. Generate DNS traffic towards those records and rotate their targets on a schedule.
3. Expose Prometheus metrics on `/metrics`.

## Project Layout

```
dns-traffic-generator/
├── cmd/
│   └── dns-traffic-generator/
│       └── main.go            # entrypoint: wiring, signals, graceful shutdown
├── internal/
│   ├── config/                # flag parsing, validation, DNS server parsing
│   ├── intent/                # last address written per record, for answer checking
│   ├── kube/                  # Kubernetes REST config (in-cluster or kubeconfig)
│   ├── metrics/               # Prometheus metrics + /metrics HTTP server
│   ├── traffic/               # DNS query load generation
│   ├── updater/               # DNSEndpoint CRD creation and target rotation
│   └── zone/                  # record naming derived from the owned subdomain
├── Dockerfile
├── Makefile
└── README.md
```

## How It Works

- Record ownership:
  - Names are derived from `-domain`: `chaos-test-<n>-<domain>` for records that must resolve and
    `chaos-test-absent-<n>-<domain>` for names that are never created and must return NXDOMAIN.
  - On startup the generator applies its own `DNSEndpoint` resources and deletes any it no longer owns.
  - Give each cluster its own subdomain: external-dns publishes every `DNSEndpoint` into every zone.
- Traffic generation:
  - Performs repeated DNS A lookups for each name against each configured DNS server.
  - Supports `udp://` and `tcp://` DNS server syntax.
  - Compares the answer against the address it last wrote, exported as the `result` label
    (`match`, `mismatch`, `untracked`).
- DNS record updates:
  - `-enable-rotation=true` patches `externaldns.k8s.io/v1alpha1` `DNSEndpoint` resources.
  - Each rotation picks a random address from `-subnet`, never the current one.
  - Uses in-cluster config when running in Kubernetes, otherwise `KUBECONFIG`/`~/.kube/config`.
- Metrics:
  - `dns_traffic_lookups_total`
  - `dns_traffic_lookup_errors_total`
  - `dns_traffic_lookup_duration_seconds`
  - `dns_traffic_record_updates_total`

## Quick Start (Local)

```bash
make build
./bin/dns-traffic-generator \
  -domain="berne.5gc.3gppnetwork.org" \
  -record-count=50 \
  -negative-count=1 \
  -subnet="11.1.1.192/27" \
  -dns-servers="udp://10.96.0.10:53" \
  -listen=":9090"
```

Open metrics:

```bash
curl http://localhost:9090/metrics
```

## Build Docker Image Locally

```bash
make docker-build
```

Run image:

```bash
make docker-run
```

## Main Flags

- `-listen`: metrics bind address (default `:9090`)
- `-interval`: DNS lookup interval (default `5s`)
- `-timeout`: DNS lookup timeout (default `3s`)
- `-dns-servers`: comma-separated DNS servers (`udp://ip:port` or `tcp://ip:port`)
- `-domain`: subdomain owned by this instance, required
- `-record-count`: number of records to create and query (default `50`)
- `-negative-count`: number of never-created names to query (default `1`)
- `-subnet`: IPv4 subnet the record targets are drawn from, required
- `-enable-rotation`: enable DNSEndpoint target rotation (default `true`)
- `-update-interval`: interval between DNSEndpoint updates (default `20s`)
- `-update-namespace`: namespace for DNSEndpoint resources (default `default`)
