#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 1

# Create 1 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 1

kubectl --context kind-berne wait deployment/coredns -n kube-system --for=condition=Available --timeout=120s

"$SCRIPT_DIR/setup-kind.sh" berne
