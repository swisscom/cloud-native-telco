#!/bin/bash
## This script sets up a fresh 3 cluster setup locally using 3 kind clusters.
## To fix a deployment, try calling setup-kind.sh with 0,1 or 2 as parameter depending on the cluster to repare.

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 3
# Create 3 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 3

kubectl --context kind-dns-0 -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-dns-1 -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-dns-2 -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s

# Deploy the multicluster dns in all 3 clusters
"$SCRIPT_DIR/setup-kind.sh" 0
"$SCRIPT_DIR/setup-kind.sh" 1
"$SCRIPT_DIR/setup-kind.sh" 2
"$SCRIPT_DIR/setup-kind.sh" 0
"$SCRIPT_DIR/setup-kind.sh" 1
