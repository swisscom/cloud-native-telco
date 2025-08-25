#!/bin/bash
# Create up to 3 kind clusters named from a fixed list: zurich, berne, lausanne

set -euo pipefail

# Colors
RED='\033[0;31m'
NC='\033[0m'

# --- args & limits ---
if [ -z "${1:-}" ]; then
  echo -e "${RED}Error: Number of clusters to create not provided${NC}"
  echo "Usage: $0 <number_of_clusters (1..3)>"
  exit 1
fi

re='^[0-9]+$'
if ! [[ "$1" =~ $re ]]; then
  echo -e "${RED}Error: '$1' is not a number${NC}" >&2
  exit 1
fi

number_of_clusters="$1"
CITIES=(berne zurich lausanne)
MAX="${#CITIES[@]}"

if [ "$number_of_clusters" -lt 1 ] || [ "$number_of_clusters" -gt "$MAX" ]; then
  echo -e "${RED}Error: number_of_clusters must be between 1 and ${MAX}${NC}"
  exit 1
fi

mkdir -p tmp

# Cross-platform in-place sed (GNU vs BSD)
sed_inplace() {
  local expr=$1 file=$2
  if command -v gsed >/dev/null 2>&1; then
    gsed -i -e "$expr" "$file"
  elif sed --version >/dev/null 2>&1; then
    sed -i -e "$expr" "$file"
  else
    sed -i '' -e "$expr" "$file"
  fi
}

# Create the requested clusters
for ((i = 0; i < number_of_clusters; i++)); do
  city="${CITIES[$i]}"
  config_file="templates/cluster-cfg.yaml"
  temp_config="tmp/cluster-${city}-cfg.yaml"

  if [ ! -f "$config_file" ]; then
    echo -e "${RED}Error: Configuration file $config_file not found${NC}"
    exit 1
  fi

  cp "$config_file" "$temp_config"

  # Give each cluster a unique API server port: 6443 + index
  sed_inplace "s/apiServerPort: 6443/apiServerPort: $((6443 + i))/g" "$temp_config"

  if kind get clusters | grep -qx "${city}"; then
    echo "Cluster '${city}' already exists. Skipping creation."
    rm -f "$temp_config"
    continue
  fi

  echo "Creating cluster '${city}'..."
  if ! kind create cluster --name "${city}" --config "$temp_config"; then
    echo -e "${RED}Error: Failed to create cluster '${city}'${NC}"
    rm -f "$temp_config"
    exit 1
  fi
  rm -f "$temp_config"

  # Wait for CoreDNS in this cluster to be ready
  kubectl --context "kind-${city}" -n kube-system \
    wait deployment/coredns --for=condition=Available --timeout=300s
done
