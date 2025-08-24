#!/bin/bash
## This script sets up a fresh 3 cluster setup locally using 3 kind clusters.
## To fix a deployment, try calling setup-kind.sh with 0,1 or 2 as parameter depending on the cluster to repare.

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 3
# Create 3 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 3

kubectl --context kind-zurich -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-berne -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s
kubectl --context kind-lausanne -n kube-system wait deployment coredns --for condition=Available=True --timeout=300s

# Deploy the multicluster dns in all 3 clusters
"$SCRIPT_DIR/setup-kind.sh" zurich
"$SCRIPT_DIR/setup-kind.sh" berne
"$SCRIPT_DIR/setup-kind.sh" lausanne
"$SCRIPT_DIR/setup-kind.sh" zurich
"$SCRIPT_DIR/setup-kind.sh" berne
