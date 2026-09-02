#!/bin/bash
# Provision the local colima VM with the settings required by the kind demos.

set -euo pipefail

PROFILE="${COLIMA_PROFILE:-default}"
CPUS="${COLIMA_CPUS:-8}"
MEMORY="${COLIMA_MEMORY:-8}"

if ! command -v colima >/dev/null 2>&1; then
  brew install colima docker kind
fi

if ! colima status --profile "$PROFILE" >/dev/null 2>&1; then
  colima start --profile "$PROFILE" -c "$CPUS" -m "$MEMORY" --network-address
fi

# Idempotent: a sysctl.d drop-in is rewritten instead of appended to.
colima ssh --profile "$PROFILE" -- sudo sh -c '
  set -e
  printf "fs.inotify.max_user_watches = 1048576\nfs.inotify.max_user_instances = 512\n" > /etc/sysctl.d/99-kind-inotify.conf
  sysctl --system >/dev/null
  command -v dig >/dev/null 2>&1 || { apt-get update && apt-get install -y dnsutils; }
'

DOCKER_SOCK="$(colima status --profile "$PROFILE" 2>&1 | awk '/socket:/ {print $NF}')"
echo
echo "colima profile '$PROFILE' is ready. Add this to your shell:"
echo "  export DOCKER_HOST=${DOCKER_SOCK}"
