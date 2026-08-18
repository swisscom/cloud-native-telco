#!/bin/bash
# End-to-end observability bootstrap.
#
#   kind-berne  prom-agent --remote-write--> kind-zurich  prom --> Grafana
#                                            172.18.2.100:9090
#
# The receiver address is a MetalLB IP out of the pool setup-kind.sh already creates for zurich
# (172.18.2.0/24), so nothing here installs MetalLB or discovers an address at runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR/install"
NS=monitoring

RED='\033[0;31m'
GREEN='\033[0;32m'
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
    echo "Create the DNS clusters first (see ../prepare-demo3-fresh.sh)."
    exit 1
  fi
}

require_cmd kubectl
require_cmd helm

echo "=== Step 0: Check the DNS clusters ==="
require_context kind-zurich
require_context kind-berne
echo "Found kind-zurich and kind-berne"

echo ""
echo "=== Step 1: Central Prometheus + Grafana on kind-zurich ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update
helm upgrade --install prom prometheus-community/kube-prometheus-stack \
  --kube-context kind-zurich \
  --namespace "$NS" --create-namespace \
  -f "$INSTALL_DIR/values.yaml"

# The chart truncates its fullname to 26 characters, so the operator Deployment is named after
# the release length. Never wait on those names -- select on app.kubernetes.io/instance.
kubectl --context kind-zurich -n "$NS" wait --for=condition=Available deployment \
  -l app.kubernetes.io/instance=prom --timeout=300s

echo ""
echo "=== Step 2: Install the Grafana dashboards ==="
install_dashboard() {
  local name=$1 file=$2
  kubectl --context kind-zurich -n "$NS" create configmap "$name" \
    --from-file="$file=$SCRIPT_DIR/dashboards/$file" \
    --dry-run=client -o yaml |
    kubectl --context kind-zurich -n "$NS" label --local -f - grafana_dashboard=1 -o yaml |
    kubectl --context kind-zurich apply -f -
}

install_dashboard dns-overview-dashboard prometheus-dashboard-ext.json
install_dashboard dns-overview-v3-dashboard prometheus-dashboard-v3.json
install_dashboard dns-simple-dashboard dashboard-simple.json

echo ""
echo "=== Step 3: Prometheus agent on kind-berne ==="
# Installed after the receiver exists, so the agent's first flush has somewhere to go.
helm upgrade --install prom-agent prometheus-community/kube-prometheus-stack \
  --kube-context kind-berne \
  --namespace "$NS" --create-namespace \
  -f "$INSTALL_DIR/agent-values.yaml"

kubectl --context kind-berne -n "$NS" wait --for=condition=Available deployment \
  -l app.kubernetes.io/instance=prom-agent --timeout=300s

echo ""
echo "=== Step 4: PodMonitors on both clusters ==="
# The same file both times: it derives the `cluster` label from the kind node name.
for context in kind-zurich kind-berne; do
  kubectl --context "$context" apply -f "$SCRIPT_DIR/monitors/dns-monitors.yaml"
done

echo ""
echo -e "${GREEN}Observability setup complete.${NC}"
echo "  kubectl --context kind-zurich -n $NS port-forward svc/prom-grafana 3000:80"
echo "  http://localhost:3000  (admin / admin)"
