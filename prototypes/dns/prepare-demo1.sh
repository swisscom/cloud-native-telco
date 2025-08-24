#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 1

# Create 1 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 1

kubectl --context kind-dns-0 wait deployment/coredns -n kube-system --for=condition=Available --timeout=120s

"$SCRIPT_DIR/setup-kind.sh" 0

# Remove the coredns debloyment in dns namespace for first demo
helm uninstall --namespace dns --kube-context kind-dns-0 coredns
# kubectl --context kind-dns-0 delete deployment coredns -n dns
