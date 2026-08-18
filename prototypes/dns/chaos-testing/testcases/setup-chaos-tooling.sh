#!/bin/bash
# Installs cert-manager (which issues the chaos-controller's admission webhook certificate) and
# the Datadog chaos-controller into both DNS clusters. Chainsaw itself is only verified, never
# installed -- it is a host-level Go binary.
#
# Usage: ./setup-chaos-tooling.sh    (no arguments, safe to re-run)

set -euo pipefail

CONTEXTS=(kind-berne kind-zurich)
CHAOS_CONTROLLER_VERSION=13.4.0
# Covers Kubernetes 1.33 to 1.36. v1.21.1 rather than v1.21.0: the latter crash-loops the
# controller on a Certificate with renewal.policy: Disabled.
CERT_MANAGER_VERSION=v1.21.1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}Error: required command not found: $cmd${NC}"
    exit 1
  fi
}

require_context() {
  local context=$1 contexts
  # Captured first: `kubectl | grep -q` dies of SIGPIPE, which pipefail turns into a false error.
  contexts="$(kubectl config get-contexts -o name)"
  if ! grep -qx "$context" <<<"$contexts"; then
    echo -e "${RED}Error: kube context not found: $context${NC}"
    echo "Create the DNS clusters first (see ../../prepare-demo3-fresh.sh)."
    exit 1
  fi
}

require_chainsaw() {
  if ! command -v chainsaw >/dev/null 2>&1; then
    echo -e "${RED}Error: chainsaw not found on PATH${NC}"
    echo "  go install github.com/kyverno/chainsaw@latest"
    echo "  export PATH=\"\$PATH:\$(go env GOPATH)/bin\""
    exit 1
  fi
}

install_chaos_tooling() {
  local context=$1 attempt

  echo ""
  echo "=== $context: cert-manager $CERT_MANAGER_VERSION ==="
  kubectl --context "$context" apply -f \
    "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

  kubectl --context "$context" -n cert-manager wait --for=condition=Available deploy --all --timeout=300s

  echo ""
  echo "=== $context: chaos-controller ==="
  # install.yaml contains a Certificate, and the cert-manager webhook is not serving the instant
  # its Deployment reports Available, so the first apply often fails. Retry.
  for attempt in 1 2 3 4 5; do
    if kubectl --context "$context" apply -f \
      "https://github.com/DataDog/chaos-controller/releases/download/${CHAOS_CONTROLLER_VERSION}/install.yaml"; then
      break
    fi
    if ((attempt == 5)); then
      echo -e "${RED}Error: chaos-controller install failed on $context after $attempt attempts${NC}"
      exit 1
    fi
    echo -e "${YELLOW}Apply failed (cert-manager webhook likely still starting), retrying in 10s...${NC}"
    sleep 10
  done

  kubectl --context "$context" -n chaos-engineering rollout status deploy/chaos-controller --timeout=300s

  echo ""
  echo "=== $context: verify the Disruption CRD ==="
  kubectl --context "$context" get crd disruptions.chaos.datadoghq.com
}

require_cmd kubectl

echo "=== Step 0: Check the clusters and the host tooling ==="
for context in "${CONTEXTS[@]}"; do
  require_context "$context"
done
require_chainsaw
echo "Found chainsaw and: ${CONTEXTS[*]}"

for context in "${CONTEXTS[@]}"; do
  install_chaos_tooling "$context"
done

echo ""
echo -e "${GREEN}Ready for chaos testing: ${CONTEXTS[*]}${NC}"
echo "  kubectl --context kind-zurich -n monitoring port-forward svc/prom-grafana 3000:80 &"
echo "  chainsaw test testcases/01-k8s-coredns/ --kube-context kind-berne"
