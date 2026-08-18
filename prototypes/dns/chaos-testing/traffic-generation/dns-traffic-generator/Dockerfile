FROM golang:1.26-alpine AS builder
ARG TARGETOS=linux
ARG TARGETARCH
WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ cmd/
COPY internal/ internal/
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o /out/dns-traffic-generator ./cmd/dns-traffic-generator

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /
COPY --from=builder /out/dns-traffic-generator /dns-traffic-generator

EXPOSE 9090
ENTRYPOINT ["/dns-traffic-generator"]
