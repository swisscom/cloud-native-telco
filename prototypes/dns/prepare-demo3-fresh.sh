#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 1
# Create 2 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 2

kubectl --context kind-dns-1 wait deployment/coredns -n kube-system --for=condition=Available --timeout=120s

# Deploy the multicluster dns in all 2 clusters
"$SCRIPT_DIR/setup-kind.sh" 0
"$SCRIPT_DIR/setup-kind.sh" 1
"$SCRIPT_DIR/setup-kind.sh" 0
