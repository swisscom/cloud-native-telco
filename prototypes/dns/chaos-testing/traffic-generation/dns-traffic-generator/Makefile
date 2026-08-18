BINARY := dns-traffic-generator
IMAGE := dns-traffic-generator:local
MAIN := ./cmd/dns-traffic-generator

.PHONY: build run test vet fmt docker-build docker-run clean

build:
	go build -o bin/$(BINARY) $(MAIN)

run:
	go run $(MAIN)

test:
	go test ./...

vet:
	go vet ./...

fmt:
	gofmt -w .

docker-build:
	docker build -t $(IMAGE) .

docker-run:
	docker run --rm -p 9090:9090 $(IMAGE)

clean:
	rm -rf bin
