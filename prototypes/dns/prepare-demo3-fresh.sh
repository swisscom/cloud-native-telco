#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 1
# Create 2 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 2

kubectl --context kind-berne -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-zurich -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-berne -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s

# Deploy the multicluster dns in all 2 clusters
"$SCRIPT_DIR/setup-kind.sh" berne
"$SCRIPT_DIR/setup-kind.sh" zurich
"$SCRIPT_DIR/setup-kind.sh" berne
