#!/bin/bash
# Starts the traffic generators in both DNS clusters. Each one creates the DNSEndpoints it
# queries and then rotates their targets.
#
# The image is never pushed to a registry, so it must be loaded into every kind cluster that
# runs it (imagePullPolicy is IfNotPresent).
#
# Usage: ./apply-traffic-generation.sh [--no-build]
#   --no-build   reuse the image already in the local docker cache instead of rebuilding it

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR_REPO="$SCRIPT_DIR/dns-traffic-generator"

BUILD_IMAGE=true
if [ "${1:-}" = "--no-build" ]; then
  BUILD_IMAGE=false
elif [ -n "${1:-}" ]; then
  echo "Usage: $(basename "$0") [--no-build]"
  exit 1
fi

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
  contexts=$(kubectl config get-contexts -o name)
  if ! grep -qx "$context" <<<"$contexts"; then
    echo -e "${RED}Error: kube context not found: $context${NC}"
    echo "Create the DNS clusters first (see ../../create-kind-clusters.sh)."
    exit 1
  fi
}

require_cmd docker
require_cmd kind
require_cmd kubectl

require_context kind-zurich
require_context kind-berne

echo "=== Step 1: Build dns-traffic-generator:local ==="
if [ "$BUILD_IMAGE" = true ]; then
  if [ ! -d "$GENERATOR_REPO" ]; then
    echo -e "${RED}Error: dns-traffic-generator checkout not found: $GENERATOR_REPO${NC}"
    exit 1
  fi
  make -C "$GENERATOR_REPO" docker-build
else
  echo "--no-build given, reusing the cached image"
  if ! docker image inspect dns-traffic-generator:local >/dev/null 2>&1; then
    echo -e "${RED}Error: image not found in the local docker cache: dns-traffic-generator:local${NC}"
    exit 1
  fi
fi

echo ""
echo "=== Step 2: Load the image into the DNS clusters ==="
for city in zurich berne; do
  echo -e "${YELLOW}Loading into $city${NC}"
  kind load docker-image dns-traffic-generator:local --name "$city"
done

echo ""
echo "=== Step 3: Apply the traffic generator manifests ==="
for city in zurich berne; do
  kubectl --context "kind-$city" -n default apply -f "$SCRIPT_DIR/traffic-generator-$city.yaml"
done

echo ""
echo "=== Step 4: Wait for rollouts ==="
for city in zurich berne; do
  kubectl --context "kind-$city" -n default rollout status "deployment/dns-traffic-generator-$city" --timeout 180s
done

echo ""
echo -e "${GREEN}Traffic generators are running.${NC}"
echo "DNSEndpoints created by the generators:"
for city in zurich berne; do
  count=$(kubectl --context "kind-$city" -n default get dnsendpoints.externaldns.k8s.io --no-headers | wc -l | tr -d ' ')
  echo "  kind-$city: $count"
done
echo "Metrics services (ClusterIP, port 9090):"
for city in zurich berne; do
  kubectl --context "kind-$city" -n default get svc "dns-traffic-generator-$city-metrics"
done
