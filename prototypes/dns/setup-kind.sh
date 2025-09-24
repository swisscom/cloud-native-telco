#!/bin/bash
# Setup a kind cluster named after a city: zurich | berne | lausanne

set -e
RED='\033[0;31m'
NC='\033[0m'
ns=dns

# ---- input & mapping ----
if [ -z "${1:-}" ]; then
  echo -e "${RED}Error: City not provided${NC}"
  echo "Usage: $0 <berne|zurich|lausanne>"
  exit 1
fi

CITY="$1"
case "$CITY" in
berne) this_cluster_id=0 ;;
zurich) this_cluster_id=1 ;;
lausanne) this_cluster_id=2 ;;
*)
  echo -e "${RED}Error: city must be one of: berne, zurich, lausanne${NC}"
  exit 1
  ;;
esac

clustername="$CITY"

# helper: return index 0/1/2 for a city name
city_index() {
  case "$1" in
  berne) echo 0 ;;
  zurich) echo 1 ;;
  lausanne) echo 2 ;;
  *) echo -1 ;;
  esac
}

# Check cluster exists
if ! kind get clusters | grep -qx "${clustername}"; then
  echo "Error: kind cluster '${clustername}' does not exist."
  exit 1
fi

echo "Setting up cluster '${clustername}' (index ${this_cluster_id})..."

# Install MetalLB
kubectl --context "kind-${clustername}" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# ---- image loading (prefer host cache; no registry if avoidable) ----
pull_image_if_not_exists() {
  local image=$1 version=$2
  if ! docker image list --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}:${version}$"; then
    docker pull "${image}:${version}"
  else
    echo "Image ${image}:${version} already exists locally. Skipping host pull."
  fi
}

# Gather nodes
NODES=()
while IFS= read -r node; do NODES+=("$node"); done < <(kind get nodes --name "$clustername")
if [ ${#NODES[@]} -eq 0 ]; then
  echo -e "${RED}No nodes found for cluster ${clustername}.${NC}"
  exit 1
fi

# Detect node arch -> platform (for fallback pulls)
NODE_ARCH=$(docker exec "${NODES[0]}" uname -m || true)
case "$NODE_ARCH" in
aarch64 | arm64) PLATFORM="linux/arm64" ;;
x86_64 | amd64) PLATFORM="linux/amd64" ;;
*) PLATFORM="linux/${NODE_ARCH}" ;;
esac
echo "Detected node arch: ${NODE_ARCH} -> using --platform ${PLATFORM}"

# Load an image ref into all nodes, preferring host->node import over network pull
load_into_kind_nodes() {
  local ref="$1" # e.g. docker.io/coredns/coredns:1.12.0
  for node in "${NODES[@]}"; do
    # Skip if already present in node’s containerd
    if docker exec "$node" ctr -n k8s.io images ls | awk '{print $1}' | grep -q "^${ref}$"; then
      echo "[$node] already has ${ref}"
      continue
    fi

    # Try to import from host cache first (no network)
    if docker image inspect "$ref" >/dev/null 2>&1; then
      echo "[$node] importing ${ref} from host cache…"
      # stream tar to node and import (no --all-platforms)
      if docker save "$ref" | docker exec -i "$node" ctr -n k8s.io images import -; then
        echo "[$node] imported ${ref} from host."
        continue
      else
        echo -e "${RED}[$node] host import failed; will try registry pull.${NC}"
      fi
    else
      echo "Host does not have ${ref}; will pull into node."
    fi

    # Fallback: pull from registry for node’s platform
    echo "[$node] pulling ${ref} from registry (${PLATFORM})…"
    if ! docker exec "$node" ctr -n k8s.io images pull --platform "${PLATFORM}" "${ref}"; then
      echo -e "${RED}[$node] failed to pull ${ref} for ${PLATFORM}.${NC}"
      return 1
    fi
  done
}

# versions
core_dns_chart_version="1.40.0"
external_dns_chart_version="8.8.0"

# ensure host images (optional)
pull_image_if_not_exists coredns/coredns "1.12.0"
pull_image_if_not_exists infoblox/dnstools "latest"
pull_image_if_not_exists registry.k8s.io/e2e-test-images/jessie-dnsutils "1.3"
pull_image_if_not_exists powerdns/pdns-auth-49 "4.9.4"
pull_image_if_not_exists bitnami/external-dns "0.16.1"
pull_image_if_not_exists bash "latest"
pull_image_if_not_exists nginx "latest"

# load into nodes (now prefers local import)
load_into_kind_nodes "docker.io/coredns/coredns:1.12.0"
load_into_kind_nodes "docker.io/infoblox/dnstools:latest" || echo -e "${RED}infoblox/dnstools may lack ${PLATFORM}.${NC}"
load_into_kind_nodes "registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3" || echo -e "${RED}jessie-dnsutils may lack ${PLATFORM}.${NC}"
load_into_kind_nodes "docker.io/powerdns/pdns-auth-49:4.9.4" || echo -e "${RED}powerdns/pdns-auth-49 may lack ${PLATFORM}.${NC}"
load_into_kind_nodes "docker.io/bitnami/external-dns:0.16.1"
load_into_kind_nodes "docker.io/library/bash:latest"
load_into_kind_nodes "docker.io/library/nginx:latest"

# Wait for metallb controller
kubectl --context "kind-${clustername}" -n metallb-system wait deployment/controller --for=condition=Available --timeout=120s
sleep 5

# Apply base + CRD
kubectl apply -k base/ --context "kind-${clustername}"
kubectl --context "kind-${clustername}" apply -f https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v0.16.1/charts/external-dns/crds/dnsendpoint.yaml

# ---- sed helper (GNU/BSD) ----
sed_inplace() {
  local expr=$1 file=$2
  if sed --version >/dev/null 2>&1; then
    sed -E -i -e "$expr" "$file"
  else
    sed -E -i '' -e "$expr" "$file"
  fi
}

# ---- IP pool per-cluster (derive from index) ----
pool_file="templates/ip-address-pool.yaml"
config_folder="tmp/cluster-${clustername}"
mkdir -p "$config_folder"
tmp_config="$config_folder/ip-address-pool.yaml"
cp "$pool_file" "$tmp_config"

pool_id=$((this_cluster_id + 1))
echo "Modifying ip pool to 172.18.${pool_id}.0/24"
sed_inplace "s|[[:space:]]*- 172\.18\.1\.0/24|    - 172.18.${pool_id}.0/24|g" "$tmp_config"

kubectl --context "kind-${clustername}" apply -f "$tmp_config"

# ---- Install external-dns in this cluster; reference others by city ----
clusters=$(kind get clusters | grep -E '^(zurich|berne|lausanne)$')

for cluster in $clusters; do
  cluster_id=$(city_index "$cluster")
  [ "$cluster_id" -lt 0 ] && continue

  values_file="templates/external-dns-values.yaml"
  config_folder="tmp/cluster-${clustername}"
  mkdir -p "$config_folder"
  tmp_config="$config_folder/external-dns-values-${cluster}.yaml"
  cp "$values_file" "$tmp_config"

  # txtOwnerId per instance
  sed_inplace "s|txtOwnerId: \"dns-\"|txtOwnerId: \"dns-${cluster}\"|g" "$tmp_config"

  if [ "$cluster" != "$clustername" ]; then
    echo "Patching external-dns values for remote cluster '${cluster}'"
    ipv4_address=$(kubectl --context "kind-${cluster}" -n "$ns" get svc pdns-ext-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    sed_inplace "s|value: \"http://pdns-service.default.svc.cluster.local:8081\"|value: http://$ipv4_address:8081|g" "$tmp_config"
    sed_inplace "s|apiUrl: http://pdns-service.default.svc.cluster.local|apiUrl: http://$ipv4_address|g" "$tmp_config"
  else
    echo "Patching external-dns values for local cluster '${clustername}'"
    sed_inplace "s|value: \"http://pdns-service.default.svc.cluster.local:8081\"|value: http://pdns-service.$ns.svc.cluster.local:8081|g" "$tmp_config"
    sed_inplace "s|apiUrl: http://pdns-service.default.svc.cluster.local|apiUrl: http://pdns-service.$ns.svc.cluster.local|g" "$tmp_config"
  fi

  RELEASE_NAME="external-dns-${cluster}"
  helm upgrade --install --namespace "$ns" --kube-context "kind-${clustername}" \
    "$RELEASE_NAME" oci://registry-1.docker.io/bitnamicharts/external-dns \
    --version "$external_dns_chart_version" -f "$tmp_config" --set "txtOwnerId=${clustername}-"

  # RBAC for DNS endpoints
  if kubectl --context "kind-${clustername}" get clusterrolebinding "dnsendpoint-read-binding-${cluster}" >/dev/null 2>&1; then
    echo "ClusterRoleBinding 'dnsendpoint-read-binding-${cluster}' exists. Skipping."
  else
    echo "Creating ClusterRoleBinding 'dnsendpoint-read-binding-${cluster}'."
    kubectl --context "kind-${clustername}" create clusterrolebinding "dnsendpoint-read-binding-${cluster}" \
      --namespace="$ns" --clusterrole=dnsendpoint-read --serviceaccount="$ns:external-dns-${cluster}"
  fi
done

# Install mariadb
kubectl --context "kind-${clustername}" apply -f base/pdns-config.yaml
helm install --namespace $ns --kube-context kind-$clustername mariadb oci://registry-1.docker.io/bitnamicharts/mariadb -f ./templates/mariadb-values.yaml

# ---- Install CoreDNS in this cluster ----ß
values_file="templates/core-dns-values.yaml"
config_folder="tmp/cluster-${clustername}"
mkdir -p "$config_folder"
tmp_config="$config_folder/core-dns-values.yaml"
cp "$values_file" "$tmp_config"

# collect PDNS external IPs from other clusters
all_ips=""
for cluster in $clusters; do
  [ "$cluster" = "$clustername" ] && continue
  ip=$(kubectl --context "kind-${cluster}" -n "$ns" get svc pdns-ext-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [ -n "$ip" ] && all_ips="$all_ips $ip"
done
all_ips="$(echo $all_ips | xargs)"
echo "all_ips is: $all_ips"

# append after 10.96.0.12 on the parameters line
sed_inplace "/parameters: 5gc.3gppnetwork.org. 10.96.0.12/ s/\$/ $all_ips/" "$tmp_config"

RELEASE_NAME=forwarder
helm repo add coredns https://coredns.github.io/helm >/dev/null 2>&1 || true
helm upgrade --install --namespace "$ns" --kube-context "kind-${clustername}" \
  --version "$core_dns_chart_version" "$RELEASE_NAME" coredns/coredns -f "$tmp_config"

# ---- Patch CoreDNS ConfigMap forwarders with other clusters' CoreDNS LB IPs ----
tmp_config="$(mktemp)"
kubectl --context "kind-${clustername}" -n kube-system get configmap coredns -o yaml >"$tmp_config"

all_ips=""
for cluster in $clusters; do
  [ "$cluster" = "$clustername" ] && continue
  ip=$(kubectl --context "kind-${cluster}" -n "$ns" get svc coredns-ext-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [ -n "$ip" ] && all_ips="$all_ips $ip"
done
all_ips="$(echo $all_ips | xargs)"
echo "all ips for forwarders: $all_ips"

sed_inplace "/^[[:space:]]*forward[[:space:]]+\.[[:space:]]+10\.96\.0\.11 .*\/etc\/resolv\.conf/ s#(10\.96\.0\.11)([[:space:]]+/etc\/resolv\.conf)#\1 $all_ips\2#" "$tmp_config"

kubectl --context "kind-${clustername}" apply -f "$tmp_config"
rm -f "$tmp_config"
