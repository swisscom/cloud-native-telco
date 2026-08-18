# DNS Chaos Testing

Tooling to generate DNS traffic, watch it, change caching behaviour and break things on purpose,
on top of the two-cluster kind environment (`kind-berne` + `kind-zurich`) described in
[../README.md](../README.md).

Nothing here needs configuring — cluster names, contexts, namespaces, ports and credentials are
hardcoded to the prototype layout.

## What is in this folder

| Folder | Use it to |
| --- | --- |
| `traffic-generation/` | Run a continuous DNS load generator in both clusters, which creates the records it queries |
| `observability/` | Install Prometheus, Grafana and the DNS dashboards |
| `cache-settings/` | Turn DNS caching on or off, which decides how visible an outage is |
| `testcases/` | Install the chaos tooling and run the resilience suites |

## Prerequisites

- The two DNS clusters from [../README.md](../README.md) (docker/colima, kind, kubectl, helm).
- **Go and make**, to build the traffic generator image. Not needed if you pass `--no-build`.
- **Chainsaw**, only for the test suites:

  ```bash
  go install github.com/kyverno/chainsaw@latest
  export PATH="$PATH:$(go env GOPATH)/bin"
  ```

## Quick Start

From this directory, in this order:

```bash
# 1. Build both DNS clusters from scratch (destructive)
(cd .. && ./prepare-demo3-fresh.sh)

# 2. Traffic generators in both clusters, which create their own DNS records
./traffic-generation/apply-traffic-generation.sh

# 3. Prometheus and Grafana on zurich, metrics agent on berne
./observability/setup-observability.sh

# 4. Chaos tooling on both clusters
./testcases/setup-chaos-tooling.sh
```

Step 1 deletes and recreates the clusters. To keep an environment you already have, use
`../prepare-demo3-continued.sh` instead.

Steps 2 to 4 are independent and can run in any order, and all of them are safe to re-run. Pass
`--no-build` to `apply-traffic-generation.sh` to reuse the `dns-traffic-generator:local` image
already in your docker cache.

## Watching what happens

Grafana is not reachable directly, so port-forward it:

```bash
kubectl --context kind-zurich -n monitoring port-forward svc/prom-grafana 3000:80
```

Open <http://localhost:3000>, log in with `admin` / `admin`, and open a DNS dashboard: "DNS
Overview" for the full picture, "DNS Simple View" for the per-cluster QPS and latency summary.
Metrics from both clusters arrive here and are told apart by a `cluster` label. Only the last hour
is kept, so anything older has aged out.

Leave the port-forward running while you execute tests — it is how they mark the dashboard.
## Changing DNS caching

Caching decides whether a DNS outage is visible at all: with caching on, clients keep resolving
from cache while the backend is down, so a chaos test may show little or no impact.

```bash
./cache-settings/apply-setting.sh no-caching berne
./cache-settings/apply-setting.sh no-caching zurich
```

The arguments are the profile (`no-caching` or `std-caching`) and the cluster (`berne` or
`zurich`), one cluster per invocation. The script applies the CoreDNS configuration and restarts
both the cluster resolver and the forwarder. Use `no-caching` before a chaos test when you want
the impact to show up immediately, and `std-caching` to show cache absorbing the outage.

## Running the chaos tests

Each suite kills a DNS component and then asserts that it recovers. A `Disruption` only reaches
pods in the cluster whose chaos-controller admitted it, so every suite runs unchanged against
either cluster — pick one with `--kube-context`, and the other keeps resolving, which is what
makes the cross-cluster failover visible on the dashboard.

```bash
chainsaw test testcases/01-k8s-coredns/ --kube-context kind-berne
chainsaw test testcases/01-k8s-coredns/ --kube-context kind-zurich
```

| Suite | Kills |
| --- | --- |
| `testcases/01-k8s-coredns/` | the cluster resolver (`kube-system/coredns`) |
| `testcases/02-forwarder/` | the forwarder (`dns/forwarder-coredns`) |
| `testcases/03-authoritative/` | PowerDNS (`dns/pdns-deployment`) |

A suite takes a few minutes: the disruption itself lasts two minutes, then recovery is asserted.
Each one annotates Grafana at start, stop and recovery so you can line the run up with the
graphs. If Grafana is not port-forwarded the test still passes, just without the markers.

Add `--skip-delete` to keep the `Disruption` object for inspection. Delete it before re-running
that suite, since disruptions are immutable:

```bash
kubectl --context kind-berne delete disruptions --all -A
```


## Manual testing

Resilience can also be exercised by hand, by scaling a DNS deployment down and back up:

```bash
kubectl --context kind-zurich -n dns scale deploy/forwarder-coredns --replicas=0
kubectl --context kind-zurich -n dns scale deploy/forwarder-coredns --replicas=1
kubectl --context kind-berne -n dns scale deploy/pdns-deployment --replicas=0
kubectl --context kind-berne -n dns scale deploy/pdns-deployment --replicas=1
```

Start `./watch-and-annotate.sh` in
another terminal first: it port-forwards Grafana and annotates the dashboard on every disruption.


## Notes

- `zurich` records resolve to `10.1.1.x`, `berne` records to `11.1.1.x`.