#!/bin/bash

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

# Install second kind cluster
"$SCRIPT_DIR/create-kind-clusters.sh" 2

# Remove the coredns debloyment in dns namespace of first cluster so it gets reinstalled
if helm list --kube-context kind-dns-0 -n dns | grep -w "coredns" >/dev/null 2>&1; then
  echo "Helm release 'coredns' is installed in kind-dns-0. Removing..."
  helm uninstall --kube-context kind-dns-0 -n dns coredns
fi

kubectl --context kind-dns-1 wait deployment/coredns -n kube-system --for=condition=Available --timeout=120s

# Deploy the multicluster dns in all 2 clusters
"$SCRIPT_DIR/setup-kind.sh" 1
"$SCRIPT_DIR/setup-kind.sh" 0
