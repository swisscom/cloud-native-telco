package main

import (
	"github.com/saschagrunert/demo"
)

func main() {
	d := demo.New()

	d.Name = "Multicluster DNS Demo"

	d.Add(demo1(), "dns-demo-2", "Forwarding")

	d.Run()
}

func demo1() *demo.Run {
	r := demo.NewRun("Demo DNS multi-cluster")

	r.Step(nil, demo.S("ls | grep .yaml"))
	r.Step(demo.S("Show logs of externalDNS-1 deployment"), demo.S("kubectl --context kind-dns-0 -n dns logs deploy/external-dns-1"))
	r.Step(demo.S("Lookup nginx in cluster 1"), demo.S("kubectl --context kind-dns-1 exec -t dnsutils -- nslookup nginx.5gc.3gppnetwork.org"))
	r.Step(demo.S("Lookup endpoint1 in cluster 1"), demo.S("kubectl --context kind-dns-1 exec -t dnsutils -- nslookup endpoint1.5gc.3gppnetwork.org"))
	r.Step(demo.S("Cat dns-enpoint-cr-2.yaml"), demo.S("cat dns-endpoint-cr-2.yaml"))
	r.Step(demo.S("Apply endpoint-cr-2 to cluster 1"), demo.S("kubectl --context kind-dns-1 apply -f dns-endpoint-cr-2.yaml"))
	r.Step(demo.S("Show logs of externalDNS-1 deployment in cluster 1"), demo.S("kubectl --context kind-dns-1 -n dns logs deploy/external-dns-1"))
	r.Step(demo.S("Show logs of externalDNS-0 deployment in cluster 1"), demo.S("kubectl --context kind-dns-1 -n dns logs deploy/external-dns-0"))
	r.Step(demo.S("Lookup endpoint2.5gc.3gppnetwork.org using default node DNS in cluster 0"), demo.S("kubectl --context kind-dns-0 exec -t dnsutils -- nslookup endpoint2.5gc.3gppnetwork.org"))
	r.Step(demo.S("Scale down powerDNS deployment to 0 in cluster 0"), demo.S("kubectl --context kind-dns-0 -n dns scale deployment pdns-deployment --replicas=0"))
	r.Step(demo.S("Lookup nginx in cluster 0"), demo.S("kubectl --context kind-dns-0 exec -t dnsutils -- nslookup nginx.5gc.3gppnetwork.org"))
	r.Step(demo.S("Apply dns-endpoint-cr-3.yaml to cluster 0"), demo.S("kubectl --context kind-dns-0 apply -f dns-endpoint-cr-3.yaml"))
	r.Step(demo.S("Lookup endpoint3.5gc.3gppnetwork.org using default node DNS in cluster 1"), demo.S("kubectl --context kind-dns-1 exec -t dnsutils -- nslookup endpoint3.5gc.3gppnetwork.org"))
	r.Step(demo.S("Lookup endpoint3.5gc.3gppnetwork.org using default node DNS in cluster 0"), demo.S("kubectl --context kind-dns-0 exec -t dnsutils -- nslookup endpoint3.5gc.3gppnetwork.org"))
	r.Step(demo.S("Scale down CoreDNS deployment in cluster 0"), demo.S("kubectl --context kind-dns-0 -n dns scale deployment coredns --replicas=0"))
	r.StepCanFail(demo.S("Lookup endpoint3.5gc.3gppnetwork.org using default node DNS in cluster 0"), demo.S("kubectl --context kind-dns-0 exec -t dnsutils -- nslookup endpoint3.5gc.3gppnetwork.org"))
	r.Step(demo.S("Lookup google.com using default node DNS in cluster 0"), demo.S("kubectl --context kind-dns-0 exec -it dnsutils -- nslookup google.com"))
	r.Step(demo.S("Scale up powerDNS deployment to 1 in cluster 0"), demo.S("kubectl --context kind-dns-0 -n dns scale deployment pdns-deployment --replicas=1"))
	r.Step(demo.S("Wait until external-dns-0 deployment in cluster 0 has restarted"), demo.S("kubectl --context kind-dns-0 -n dns wait --for=condition=available deploy/external-dns-0"))
	r.Step(demo.S("Show logs of externalDNS-0 deployment in cluster 0"), demo.S("kubectl --context kind-dns-0 -n dns logs deploy/external-dns-0"))
	return r
}
