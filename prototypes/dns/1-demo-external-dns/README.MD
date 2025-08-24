# Demo 1: ExternalDNS & PowerDNS Single Cluster

![PowerDNS & ExternalDNS](powerdns-and-externaldns.png "PowerDNS & ExternalDNS")

## Demo Preparation

Before the demo, execute the prepare-demo1.sh script in the parent folder.

## Auto Demo

This demo can be run using https://github.com/saschagrunert/demo, execute first the build command and then start the demo-1 exec with the -l flag. For more options see -h:

```
go build .
./demo-1 -l
```

## Manual Demo


### 1. Show pods

```
kubectl get pods -n dns
```

### 2. Show some-svc.yaml file

```
cat some-svc.yaml
```

### 3. Apply svc.yaml

```
kubectl apply -f svc.yaml
```

### 4. Check ExternalDNS logs

```
kubectl -n dns logs deploy/external-dns-0 --tail 10
```

### 5. Dig PowerDNS for nginx record

```
kubectl exec -it dnsutils -- dig +noall +answer nginx.5gc.3gppnetwork.org @10.96.0.12
```

### 6. Show dns-endpoint-cr.yaml

```
cat dns-endpoint-cr.yaml
```

### 7. Apply dns-endpoint-cr.yaml
```
kubectl apply -f dns-endpoint-cr.yaml
```

### 4. Check ExternalDNS logs

```
kubectl -n dns logs deploy/external-dns-0 --tail 10
```

### 8. Dig PowerDNS for endpoint1 record
```
kubectl exec -it dnsutils -- dig +noall +answer endpoint1.5gc.3gppnetwork.org @10.96.0.12
```
