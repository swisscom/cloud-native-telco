#!/bin/bash

# This script will reapply the yaml files for the dns demo deployment, it can be used to continue the demo2 without removing the kind cluster and thus leaving the resources applied in the previous demo.

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

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
