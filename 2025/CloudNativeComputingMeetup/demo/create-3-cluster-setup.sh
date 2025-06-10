#!/bin/bash
## This script sets up a fresh 3 cluster setup locally using 3 kind clusters.
## To fix a deployment, try calling setup-kind.sh with 0,1 or 2 as parameter depending on the cluster to repare.

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 3
# Create 3 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 3

DEPLOYMENT_NAME="coredns"
NAMESPACE="kube-system"
while true; do
  # Check if the deployment is ready
  READY_REPLICAS=$(kubectl --context kind-dns-1 get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  DESIRED_REPLICAS=$(kubectl --context kind-dns-1 get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.replicas}')

  if [[ "$READY_REPLICAS" == "$DESIRED_REPLICAS" ]] && [[ "$READY_REPLICAS" -gt 0 ]]; then
    echo "Deployment $DEPLOYMENT_NAME is ready."
    break
  else
    echo "Waiting... Ready replicas: $READY_REPLICAS / $DESIRED_REPLICAS"
    sleep 5
  fi
done

# Deploy the multicluster dns in all 3 clusters
"$SCRIPT_DIR/setup-kind.sh" 0
"$SCRIPT_DIR/setup-kind.sh" 1
"$SCRIPT_DIR/setup-kind.sh" 2
"$SCRIPT_DIR/setup-kind.sh" 0
"$SCRIPT_DIR/setup-kind.sh" 1
