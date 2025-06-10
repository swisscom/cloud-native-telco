package main

import (
	"github.com/saschagrunert/demo"
)

func main() {
	d := demo.New()

	d.Name = "Demo DNS forwarding by CoreDNS"

	d.Add(demo1(), "dns-demo-2", "Forwarding")

	d.Run()
}

func demo1() *demo.Run {
	r := demo.NewRun("Demo DNS forwarding by CoreDNS")

	r.Step(demo.S("Show pods in dns namespace"), demo.S("kubectl get pods -n dns"))
	r.Step(demo.S("Show new coredns configmap in dns namespace"), demo.S("kubectl describe cm/coredns -n dns"))
	r.Step(demo.S("Show services in dns namespace"), demo.S("kubectl get svc -n dns"))
	r.Step(demo.S("Show kube-system coredns configmap"), demo.S("kubectl describe cm/coredns -n kube-system"))
	r.Step(demo.S("Lookup nginx.5gc.3gppnetwork.org using default node DNS"), demo.S("kubectl exec -t dnsutils -- nslookup nginx.5gc.3gppnetwork.org"))
	r.Step(demo.S("Nslookup endpoint1.5gc.3gppnetwork.org using default node DNS"), demo.S("kubectl exec -it dnsutils -- nslookup endpoint1.5gc.3gppnetwork.org"))
	return r
}
