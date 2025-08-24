#!/bin/bash

# This script sets up the specified kind cluster with the necessary components and copies all the required configuration files into the tmp folder.
# During the demo we create a 2 kind cluster deployment but this script also supports setting up deployments with more than 2 clusters.

set -e
# Define colors
RED='\033[0;31m'
NC='\033[0m' # No Color

ns=dns

# Check if id of cluster is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: Id of cluster to setup not provided${NC}"
  echo "Usage: $0 <id_of_cluster> [clusternameprefix]"
  exit 1
fi

# Check if the first parameter is a number
re='^[0-9]+$'
if ! [[ $1 =~ $re ]]; then
  echo -e "${RED}Error: '$1' is not a number${NC}" >&2
  exit 1
fi

this_cluster_id=$1
clusternameprefix=${2:-dns} # Set default cluster name to 'dns' if not provided

clustername="${clusternameprefix}-$this_cluster_id"

# Check if kind cluster exists
if ! kind get clusters | grep -q "^${clustername}$"; then
  echo "Error: Kind cluster '${clustername}' does not exist."
  exit 1
fi

echo "Setting up cluster '$clustername'..."

# Install Metallb
kubectl --context kind-$clustername apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

# Pull & load images into kind nodes (platform-correct, no --all-platforms)
pull_image_if_not_exists() {
  local image=$1
  local version=$2
  if ! docker image list --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}:${version}$"; then
    docker pull "${image}:${version}"
  else
    echo "Image ${image}:${version} already exists locally. Skipping host pull."
  fi
}

# Detect nodes & platform
# mapfile -t NODES < <(kind get nodes --name "$clustername")
NODES=()
while IFS= read -r node; do
  NODES+=("$node")
done < <(kind get nodes --name "$clustername")

if [ ${#NODES[@]} -eq 0 ]; then
  echo -e "${RED}No nodes found for cluster ${clustername}.${NC}"
  exit 1
fi

# Use the first node to detect arch
NODE_ARCH=$(docker exec "${NODES[0]}" uname -m)
case "$NODE_ARCH" in
  aarch64|arm64)   PLATFORM="linux/arm64" ;;
  x86_64|amd64)    PLATFORM="linux/amd64" ;;
  *)               PLATFORM="linux/${NODE_ARCH}";;
esac
echo "Detected node arch: ${NODE_ARCH} -> using --platform ${PLATFORM}"

# Load one image ref into all nodes via containerd
load_into_kind_nodes() {
  local ref="$1"   # e.g. coredns/coredns:1.12.0
  for node in "${NODES[@]}"; do
    # Fast-path: skip if present
    if docker exec "$node" ctr -n k8s.io images ls | awk '{print $1}' | grep -q "^${ref}$"; then
      echo "[$node] already has ${ref}"
      continue
    fi
    echo "[$node] pulling ${ref} into containerd (${PLATFORM})…"
    # Note: we don’t use --all-platforms; only the node’s platform
    if ! docker exec "$node" ctr -n k8s.io images pull --platform "${PLATFORM}" "${ref}"; then
      echo -e "${RED}[$node] failed to pull ${ref} for ${PLATFORM}.${NC}"
      echo "Tip: some images are not built for ${PLATFORM}. Use a multi-arch alternative."
      return 1
    fi
  done
}

# ---- declare versions ----
core_dns_chart_version="1.40.0"
external_dns_chart_version="8.8.0"

# ---- ensure images exist on host (optional) ----
pull_image_if_not_exists coredns/coredns "1.12.0"
pull_image_if_not_exists infoblox/dnstools "latest"
pull_image_if_not_exists registry.k8s.io/e2e-test-images/jessie-dnsutils "1.3"
pull_image_if_not_exists powerdns/pdns-auth-49 "4.9.4"
pull_image_if_not_exists bitnami/external-dns "0.16.1"
pull_image_if_not_exists bash "latest"
pull_image_if_not_exists nginx "latest"

# ---- load into nodes (platform-correct) ----
load_into_kind_nodes "docker.io/coredns/coredns:1.12.0"
load_into_kind_nodes "docker.io/infoblox/dnstools:latest" || echo -e "${RED}infoblox/dnstools may not have ${PLATFORM}. Consider ghcr.io/dns-tool/dnsutils or praqma/network-multitool.${NC}"
load_into_kind_nodes "registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3" || echo -e "${RED}jessie-dnsutils may not have ${PLATFORM}. Consider ghcr.io/infisical/dnsutils or alpine:latest + bind-tools.${NC}"
load_into_kind_nodes "docker.io/powerdns/pdns-auth-49:4.9.4" || echo -e "${RED}powerdns/pdns-auth-49 may not have ${PLATFORM}.${NC}"
load_into_kind_nodes "docker.io/bitnami/external-dns:0.16.1"
load_into_kind_nodes "docker.io/library/bash:latest"
load_into_kind_nodes "docker.io/library/nginx:latest"


# Wait for the controller deployment to be ready
kubectl --context kind-$clustername wait deployment/controller -n metallb-system --for=condition=Available --timeout=120s

sleep 5

# Apply the base yaml files and the external-dns crd
kubectl apply -k base/ --context kind-$clustername
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/external-dns/v0.16.1/charts/external-dns/crds/dnsendpoint.yaml --context kind-$clustername

# Prepare the ip pool configuration file
pool_file="templates/ip-address-pool.yaml"
config_folder="tmp/cluster-$this_cluster_id"
mkdir -p $config_folder
tmp_config="$config_folder/ip-address-pool.yaml"
cp "$pool_file" "$tmp_config"

# Modify ip pool in the copied config file depending on cluster id
pool_id=$((this_cluster_id + 1))
echo "Modifying ip pool in the copied config file to 172.18.$pool_id.0/24"

# Cross-platform in-place sed (GNU vs BSD)
sed_inplace() {
  local expr=$1 file=$2
  if sed --version >/dev/null 2>&1; then
    # GNU sed (Linux)
    sed -E -i -e "$expr" "$file"
  else
    # BSD sed (macOS)
    sed -E -i '' -e "$expr" "$file"
  fi
}

sed_inplace "s|[[:space:]]*- 172\.18\.1\.0/24|    - 172.18.$pool_id.0/24|g" "$tmp_config"

# Apply the ip pool configuration
kubectl apply -f $tmp_config --context kind-$clustername

# Install external-dns
clusters=$(kind get clusters | grep dns)

for cluster in $clusters; do
  cluster_id=${cluster: -1}

  # Prepare the external-dns configuration file
  values_file="templates/external-dns-values.yaml"
  config_folder="tmp/cluster-$this_cluster_id"
  mkdir -p $config_folder
  tmp_config="$config_folder/external-dns-values-$cluster_id.yaml"

  cp "$values_file" "$tmp_config"

  # Modify txtOwnerId in the copied config file for each external-dns instance
  sed_inplace "s|txtOwnerId: \"dns-\"|txtOwnerId: \"dns-$cluster_id\"|g" "$tmp_config"

  if [ "$cluster_id" != "$this_cluster_id" ]; then
    # Modify ip in the copied config file with the loadbalancer ip of the pdns service from the other clusters
    echo "Modifying apiServerPort in the copied config file and the namespace is $ns"
    ipv4_address=$(kubectl --context kind-dns-$cluster_id get svc pdns-ext-service -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    sed_inplace "s|value: \"http://pdns-service.default.svc.cluster.local:8081\"|value: http://$ipv4_address:8081|g" "$tmp_config"
    sed_inplace "s|apiUrl: http://pdns-service.default.svc.cluster.local|apiUrl: http://$ipv4_address|g" "$tmp_config"
  else
    # Modify ip in the copied config file with the loadbalancer ip of the pdns service from this cluster
    echo "Modifying apiServerPort in the copied config file and the namespace is $ns"
    sed_inplace "s|value: \"http://pdns-service.default.svc.cluster.local:8081\"|value: http://pdns-service.$ns.svc.cluster.local:8081|g" "$tmp_config"
    sed_inplace "s|apiUrl: http://pdns-service.default.svc.cluster.local|apiUrl: http://pdns-service.$ns.svc.cluster.local|g" "$tmp_config"
  fi

  RELEASE_NAME=external-dns-$cluster_id
  helm upgrade --install --namespace $ns --kube-context kind-$clustername $RELEASE_NAME oci://registry-1.docker.io/bitnamicharts/external-dns --version $external_dns_chart_version -f $tmp_config --set txtOwnerId=$clustername-
  # Create a rolebinding for the external-dns service account to allow read of the dnsendpoints crd if it does not exist
  if kubectl --context kind-$clustername get clusterrolebinding dnsendpoint-read-binding-$cluster_id >/dev/null 2>&1; then
    echo "ClusterRoleBinding 'dnsendpoint-read-binding-$cluster_id' already exists. Skipping creation."
  else
    echo "Creating ClusterRoleBinding 'dnsendpoint-read-binding-$cluster_id'."
    kubectl --context kind-$clustername create clusterrolebinding dnsendpoint-read-binding-$cluster_id --namespace=dns --clusterrole=dnsendpoint-read --serviceaccount=dns:external-dns-$cluster_id
  fi
done

# Install CoreDNS
values_file="templates/core-dns-values.yaml"
config_folder="tmp/cluster-$this_cluster_id"
mkdir -p $config_folder
tmp_config="$config_folder/core-dns-values.yaml"
cp "$values_file" "$tmp_config"

# Collect all the IPs from the other clusters
all_ips=""
for cluster in $clusters; do
  cluster_id=${cluster: -1}
  if [ "$cluster_id" != "$this_cluster_id" ]; then
    ip=$(kubectl --context kind-dns-$cluster_id get svc pdns-ext-service -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    [ -n "$ip" ] && all_ips="$all_ips $ip"
  fi
done
all_ips="$(echo $all_ips | xargs)" # trim whitespace

echo "all_ips is: $all_ips"

# Inject all IPs after 10.96.0.12 but before /etc/resolv.conf
# sed -i '' -E "/parameters: 5gc.3gppnetwork.org. 10.96.0.12 / s#(10\.96\.0\.12)([[:space:]]+/etc/resolv\.conf)#\1 $all_ips\2#" "$tmp_config"

sed_inplace "/parameters: 5gc.3gppnetwork.org. 10.96.0.12/ s/$/ $all_ips/" "$tmp_config"

echo "tmp_config: $tmp_config"

RELEASE_NAME=coredns
helm repo add coredns https://coredns.github.io/helm
helm upgrade --install --namespace $ns --kube-context kind-$clustername --version $core_dns_chart_version $RELEASE_NAME coredns/coredns -f $tmp_config

tmp_config=$(mktemp)

# 1. Fetch the current CoreDNS ConfigMap from *this* cluster
kubectl --context kind-$clustername -n kube-system \
  get configmap coredns -o yaml >"$tmp_config"

# 2. Walk the other clusters and patch the forward line
all_ips=""
for cluster in $clusters; do
  cluster_id=${cluster: -1}
  if [ "$cluster_id" != "$this_cluster_id" ]; then
    ip=$(kubectl --context "kind-dns-$cluster_id" \
      -n dns \
      get svc coredns-ext-service \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    [ -n "$ip" ] && all_ips="$all_ips $ip"
  fi
done
all_ips="$(echo $all_ips | xargs)" # trim leading/trailing whitespace

echo "all ips: $all_ips"

sed_inplace "/^[[:space:]]*forward[[:space:]]+\.[[:space:]]+10\.96\.0\.11 .*\/etc\/resolv\.conf/ s#(10\.96\.0\.11)([[:space:]]+/etc/resolv\.conf)#\1 $all_ips\2#" "$tmp_config"

#for cluster in $clusters; do
#  cluster_id=${cluster: -1}

#  if [ "$cluster_id" != "$this_cluster_id" ]; then
# LoadBalancer IP of CoreDNS in the *other* cluster
#    ipv4_address=$(kubectl --context "kind-dns-$cluster_id" \
#      -n dns \
#      get svc coredns-ext-service \
#      -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
# Append that IP right after 10.96.0.11 but before /etc/resolv.conf
# – keeps the spacing intact and is safe for GNU *and* BSD sed.
# sed -i'' -e "/forward: . 10.96.0.11/ s/$/ $ipv4_address/" "$tmp_config"
#    tmp_out=$(mktemp)
#    awk -v ip="$ipv4_address" '
# Look for a line containing "forward . 10.96.0.11" and " /etc/resolv.conf"
#      /^[[:space:]]*forward[[:space:]]+\.[[:space:]]+10\.96\.0\.11 .*\/etc\/resolv\.conf/ {
# Replace "10.96.0.11" with "10.96.0.11 <ip>"
#        sub(/10\.96\.0\.11/, "10.96.0.11 " ip)
#      }
#      { print }
#    ' "$tmp_config" >"$tmp_out" && mv "$tmp_out" "$tmp_config"

#  fi
#done
# 3. Apply the modified ConfigMap back to *this* cluster
kubectl --context kind-$clustername apply -f "$tmp_config"
rm -f "$tmp_config"
