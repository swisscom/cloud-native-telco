#!/usr/bin/env bash
set -euo pipefail

# Applies a CoreDNS caching profile to one cluster and restarts both resolvers.
# Usage: apply-setting.sh <profile: no-caching|std-caching> <cluster-name>
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <profile: no-caching|std-caching> <cluster-name> e.g., berne" >&2
    exit 1
fi

PROFILE=$1
CLUSTER_NAME=$2
CONTEXT="kind-$CLUSTER_NAME"

if [ "$PROFILE" != "no-caching" ] && [ "$PROFILE" != "std-caching" ]; then
    echo "Invalid profile '$PROFILE'. Allowed: no-caching or std-caching" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/$PROFILE/$CLUSTER_NAME"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Target directory '$TARGET_DIR' does not exist. Check profile and cluster name." >&2
    exit 1
fi

kubectl --context "$CONTEXT" apply -f "$TARGET_DIR"
echo "Applied $PROFILE settings to the $CLUSTER_NAME cluster"

kubectl --context "$CONTEXT" rollout restart deployment coredns -n kube-system
kubectl --context "$CONTEXT" rollout status deployment/coredns -n kube-system --timeout=120s || \
    echo "Warning: coredns did not become ready within 120s"

kubectl --context "$CONTEXT" rollout restart deployment forwarder-coredns -n dns
kubectl --context "$CONTEXT" rollout status deployment/forwarder-coredns -n dns --timeout=120s || \
    echo "Warning: forwarder-coredns did not become ready within 120s"

echo "Completed apply + restarts for profile='$PROFILE' cluster='$CLUSTER_NAME'"
