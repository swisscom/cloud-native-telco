# Demo 3 Multi-cluster DNS

[Demo 3 recording](https://youtu.be/CR8R3cOCLXc?si=gcoYWjIChXGIhiRW&t=1232)

![dual-cluster-dns-arch](2-cluster-dns-arch.png "Dual Cluster DNS Architecture")

## Demo Preparation

Before the demo, execute `make demo3` or `make demo3-fresh` in the parent folder.

## Interactive Diagram

```bash
uv run --directory prototypes/dns/3-demo-multi-cluster-dns/dashboard python dns_dashboard.py
```

## Demo creation when everything is operational

```bash
# Lookup endpoint2 to confirm it doesn't yet exist
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer  endpoint2.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer  endpoint2.5gc.3gppnetwork.org

# apply DNS Resource "endpoint2.5gc.3gppnetwork.org" to Zurich cluster
cat dns-endpoint-cr-2.yaml
kubectl --context kind-zurich apply -f dns-endpoint-cr-2.yaml

# Show logs of ExternalDNS deployments in zurich
echo "berne:"  && {kubectl --context kind-zurich -n dns logs deploy/external-dns-zurich | tail}
echo "zurich:" && {kubectl --context kind-zurich -n dns logs deploy/external-dns-berne | tail}

# Lookup endpoint2
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer  endpoint2.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer  endpoint2.5gc.3gppnetwork.org
```

### Show fully operational system while site Berne is degraded

```bash
# Lookup endpoint3 to confirm it doesn't yet exist
echo "berne:"  && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org

# Scale down PowerDNS deployment to 0 in berne
kubectl --context kind-berne -n dns scale deployment pdns-deployment --replicas=0

# Show deployments
echo "berne:"  && kubectl --context kind-berne -n dns get deploy
echo "zurich:" && kubectl --context kind-zurich -n dns get deploy

# apply DNS Resource "endpoint3.5gc.3gppnetwork.org" to Berne cluster
cat dns-endpoint-cr-3.yaml
kubectl --context kind-berne apply -f dns-endpoint-cr-3.yaml

# Lookup endpoint3
echo "berne:"  && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
# both succeed because cross cluster forwarding.
```

### Further degrade site Berne by scaleing down coredns forwarder deployment to 0

```bash
# scale down forwarder in berne
kubectl --context kind-berne -n dns scale deployment forwarder-coredns --replicas=0

# Show deployments
echo "berne:"  && kubectl --context kind-berne -n dns get deploy
echo "zurich:" && kubectl --context kind-zurich -n dns get deploy

# Lookup endpoint3
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
```

### Scale down coredns forwarder deployment to 0 in zurich

```bash
# scale down zurich forwarder
kubectl --context kind-zurich -n dns scale deployment forwarder-coredns --replicas=0

# Show deployments
echo "berne:"  && kubectl --context kind-berne -n dns get deploy
echo "zurich:" && kubectl --context kind-zurich -n dns get deploy

# Lookup endpoint3
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org

# Lookup google.com
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer google.com
echo "zurich:" && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer google.com
```

## Restore

### Scale up coredns forwarder deployment to 1 in zurich

```bash
# scale restore forwarder in zurich
kubectl --context kind-zurich -n dns scale deployment forwarder-coredns --replicas=1

# Show deployments
echo "berne:"  && kubectl --context kind-berne -n dns get deploy
echo "zurich:" && kubectl --context kind-zurich -n dns get deploy

# check if lookup works
echo "berne:"  && kubectl --context kind-berne exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
echo "zurich:" && kubectl --context kind-zurich exec -it dnsutils -- dig +noall +answer endpoint3.5gc.3gppnetwork.org
```

### Restore everything

```bash
# scale back all deployments and delete dns-endpoint
kubectl --context kind-zurich -n dns scale deployment forwarder-coredns --replicas=1
kubectl --context kind-berne -n dns scale deployment pdns-deployment --replicas=1
kubectl --context kind-berne -n dns scale deployment forwarder-coredns --replicas=1
kubectl --context kind-zurich delete -f dns-endpoint-cr-2.yaml
kubectl --context kind-berne delete -f dns-endpoint-cr-3.yaml
```
