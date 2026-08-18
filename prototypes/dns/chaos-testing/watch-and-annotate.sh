#!/usr/bin/env bash
# Port-forwards Grafana to http://localhost:3000 and, for as long as it runs, annotates it
# whenever a Deployment is scaled or a pod becomes ready in either cluster. Start it in its own
# terminal at the beginning of a demo and leave it there; Ctrl-C stops the port-forward and the
# watches. It replaces the manual port-forward the chaos suites need, so nothing else is required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANNOTATE="$SCRIPT_DIR/testcases/utils/annotate-grafana.sh"
CLUSTERS=(berne zurich)

GRAFANA_URL=http://localhost:3000
# The stack's own credentials, the same ones annotate-grafana.sh posts with.
GRAFANA_AUTH=admin:admin

# Watches fire on every status update, not just the changes we care about. Remembering the last
# seen value per object turns that stream into transitions. One file per object instead of an
# associative array, because the `while read` loops run in subshells.
STATE_DIR="$(mktemp -d)"

# PIDs of the supervisor loops below, so cleanup can stop them before their children.
PIDS=()

DEPLOY_COLUMNS='custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas'
POD_COLUMNS='custom-columns=NS:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'

cleanup() {
  trap - EXIT INT TERM
  echo
  echo "Stopping the watches and the port-forward..."
  # Tell the supervisors to stop before anything is killed, otherwise they restart it.
  touch "$STATE_DIR/stopping" 2>/dev/null || true
  if [[ ${#PIDS[@]} -gt 0 ]]; then
    kill "${PIDS[@]}" 2>/dev/null || true
  fi
  # Killing a backgrounded pipeline only kills the `while read` end and leaves kubectl running,
  # so match the watch processes themselves.
  pkill -f -- "--watch-only" 2>/dev/null || true
  pkill -f -- "port-forward svc/prom-grafana" 2>/dev/null || true
  rm -rf "$STATE_DIR"
}
trap cleanup EXIT INT TERM

# kubectl exits when the API server closes a watch, which it does periodically, and the
# port-forward exits when the Grafana pod restarts. Either one dying is otherwise completely
# silent: the script stays up and simply stops noticing that cluster, which during a demo looks
# like the disruption was never detected. Restart whatever ends, and say so.
supervise() {
  local label=$1
  shift
  while [[ ! -e "$STATE_DIR/stopping" ]]; do
    "$@" || true
    if [[ -e "$STATE_DIR/stopping" ]]; then
      break
    fi
    echo "[$label] stopped, restarting" >&2
    sleep 2
  done
}

port_forward() {
  kubectl --context kind-zurich -n monitoring port-forward svc/prom-grafana 3000:80
}

annotate() {
  "$ANNOTATE" "$1"
}

seed_state() {
  local cluster=$1
  kubectl --context "kind-$cluster" get deployments -A --no-headers -o "$DEPLOY_COLUMNS" |
    while read -r ns name replicas; do
      echo "$replicas" >"$STATE_DIR/deploy_${cluster}_${ns}_${name}"
    done
  kubectl --context "kind-$cluster" get pods -A --no-headers -o "$POD_COLUMNS" |
    while read -r ns name ready; do
      echo "$ready" >"$STATE_DIR/pod_${cluster}_${ns}_${name}"
    done
}

watch_deployments() {
  local cluster=$1
  kubectl --context "kind-$cluster" get deployments -A --watch-only --no-headers -o "$DEPLOY_COLUMNS" |
    while read -r ns name replicas; do
      key="$STATE_DIR/deploy_${cluster}_${ns}_${name}"
      previous="$(cat "$key" 2>/dev/null || true)"
      echo "$replicas" >"$key"

      # No previous value means the Deployment was created just now, which is not a scale event.
      if [[ -z "$previous" || "$previous" == "$replicas" ]]; then
        continue
      fi
      if ((replicas < previous)); then
        annotate "$cluster $ns/$name scaled down $previous -> $replicas"
      else
        annotate "$cluster $ns/$name scaled up $previous -> $replicas"
      fi
    done
}

watch_pods() {
  local cluster=$1
  kubectl --context "kind-$cluster" get pods -A --watch-only --no-headers -o "$POD_COLUMNS" |
    while read -r ns name ready; do
      key="$STATE_DIR/pod_${cluster}_${ns}_${name}"
      previous="$(cat "$key" 2>/dev/null || true)"
      echo "$ready" >"$key"

      # Every pod alive at startup was seeded, so a pod with no previous value is new and its
      # first Ready=True sighting is a real transition.
      if [[ "$ready" == "True" && "$previous" != "True" ]]; then
        annotate "$cluster $ns/$name ready"
      fi
    done
}

grafana_up() {
  curl -fsS --max-time 2 -u "$GRAFANA_AUTH" "$GRAFANA_URL/api/health" >/dev/null 2>&1
}

echo "=== Exposing Grafana on $GRAFANA_URL ==="
supervise "port-forward" port_forward &
PIDS+=($!)

for _ in $(seq 30); do
  if grafana_up; then
    break
  fi
  sleep 1
done
if ! grafana_up; then
  echo "Grafana did not come up on $GRAFANA_URL. Is the observability stack installed?" >&2
  exit 1
fi
echo "Grafana is on $GRAFANA_URL, log in with admin / admin"

echo "=== Watching both clusters ==="
for cluster in "${CLUSTERS[@]}"; do
  seed_state "$cluster"
done
for cluster in "${CLUSTERS[@]}"; do
  supervise "$cluster deployments" watch_deployments "$cluster" &
  PIDS+=($!)
  supervise "$cluster pods" watch_pods "$cluster" &
  PIDS+=($!)
done

echo "Annotating Grafana on Deployment scale up, scale down and pod ready. Ctrl-C to stop."
wait
