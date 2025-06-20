#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Destroy the single kind cluster
"$SCRIPT_DIR/destroy-kind.sh" 1

# Create 1 kind clusters
"$SCRIPT_DIR/create-kind-clusters.sh" 1

DEPLOYMENT_NAME="coredns"
NAMESPACE="kube-system"
while true; do
  # Check if the deployment is ready
  READY_REPLICAS=$(kubectl --context kind-dns-0 get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
  DESIRED_REPLICAS=$(kubectl --context kind-dns-0 get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.replicas}')
  
  if [[ "$READY_REPLICAS" == "$DESIRED_REPLICAS" ]] && [[ "$READY_REPLICAS" -gt 0 ]]; then
    echo "Deployment $DEPLOYMENT_NAME is ready."
    break
  else
    echo "Waiting... Ready replicas: $READY_REPLICAS / $DESIRED_REPLICAS"
    sleep 5
  fi
done


"$SCRIPT_DIR/setup-kind.sh" 0

# Remove the coredns debloyment in dns namespace for first demo
helm uninstall --namespace dns --kube-context kind-dns-0 coredns
# kubectl --context kind-dns-0 delete deployment coredns -n dns
