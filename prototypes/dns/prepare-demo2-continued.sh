#!/bin/bash

# This script will reapply the yaml files for the dns demo deployment, it can be used to continue the demo2 without removing the kind cluster and thus leaving the resources applied in the previous demo.

# Get the directory of the current script
SCRIPT_DIR=$(dirname "$0")

kubectl --context kind-zurich wait deployment/coredns -n kube-system --for=condition=Available --timeout=120s

"$SCRIPT_DIR/setup-kind.sh" zurich
