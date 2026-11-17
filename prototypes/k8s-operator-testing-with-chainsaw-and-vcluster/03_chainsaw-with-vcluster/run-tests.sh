#!/usr/bin/env bash
# Runs every chainsaw test suite in its own ephemeral vcluster, in parallel:
#   create vcluster -> chainsaw test -> delete vcluster
#
# Usage:
#   ./run-tests.sh                      # all suites (every folder containing a chainsaw-test.yaml)
#   ./run-tests.sh basic cloudnative-pg # selected suites
#
# Environment:
#   KEEP_VCLUSTERS=true   keep the vclusters after the run (for debugging)
#   REPORT_DIR=<path>     where logs and JUnit reports are written (default: ./.reports/<run-id>)
#
# Uses the current kubectl context as the host cluster.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

KEEP_VCLUSTERS="${KEEP_VCLUSTERS:-false}"
RUN_ID="$(date +%H%M%S)"
REPORT_DIR="${REPORT_DIR:-$SCRIPT_DIR/.reports/$RUN_ID}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

for bin in kubectl vcluster chainsaw helm; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo -e "${RED}Missing required tool: ${bin}${NC}" >&2
    exit 1
  fi
done

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo -e "${RED}Host cluster not reachable (context: $(kubectl config current-context 2>/dev/null || echo none)).${NC}" >&2
  echo "Create one with: kind create cluster --name chainsaw-vcluster-demo" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  SUITES=("$@")
else
  SUITES=()
  for f in */chainsaw-test.yaml; do SUITES+=("$(dirname "$f")"); done
fi

mkdir -p "$REPORT_DIR"

vcluster_name() { echo "chainsaw-$1-$RUN_ID"; }

cleanup() {
  [ "$KEEP_VCLUSTERS" = "true" ] && return
  for suite in "${SUITES[@]}"; do
    local name
    name="$(vcluster_name "$suite")"
    vcluster delete "$name" --namespace "$name" --ignore-not-found >/dev/null 2>&1 &
  done
  wait
}
trap 'echo; echo "Interrupted, deleting vclusters..."; cleanup; exit 130' INT TERM

run_suite() {
  local suite="$1"
  local name
  name="$(vcluster_name "$suite")"
  local log="$REPORT_DIR/$suite.log"
  local start=$SECONDS rc

  (
    echo "### [$suite] creating vcluster $name"
    vcluster create "$name" --namespace "$name" --connect=false &&
      kubectl rollout status statefulset/"$name" --namespace "$name" --timeout=5m &&
      echo "### [$suite] running chainsaw inside vcluster $name" &&
      vcluster connect "$name" --namespace "$name" --silent -- \
        chainsaw test \
        --test-dir "$suite" \
        --config .chainsaw.yaml \
        --no-color \
        --report-format JUNIT-TEST \
        --report-path "$REPORT_DIR" \
        --report-name "$suite"
    rc=$?

    if [ "$KEEP_VCLUSTERS" = "true" ]; then
      echo "### [$suite] keeping vcluster: vcluster connect $name --namespace $name"
    else
      echo "### [$suite] deleting vcluster $name"
      vcluster delete "$name" --namespace "$name"
    fi
    exit $rc
  ) >"$log" 2>&1
  rc=$?

  local duration=$((SECONDS - start))
  if [ $rc -eq 0 ]; then
    echo -e "${GREEN}✔ ${suite}${NC} passed in ${duration}s"
  else
    echo -e "${RED}✘ ${suite}${NC} failed in ${duration}s (log: $log)"
    tail -n 30 "$log" | sed 's/^/    /'
  fi
  return $rc
}

echo -e "${BLUE}Host context:${NC} $(kubectl config current-context)"
echo -e "${BLUE}Suites:${NC}       ${SUITES[*]}"
echo -e "${BLUE}Reports:${NC}      $REPORT_DIR"
echo

pids=()
for suite in "${SUITES[@]}"; do
  if [ ! -f "$suite/chainsaw-test.yaml" ]; then
    echo -e "${RED}No chainsaw-test.yaml in '$suite'${NC}" >&2
    exit 1
  fi
  echo -e "▶ ${suite} started in vcluster $(vcluster_name "$suite")"
  run_suite "$suite" &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=$((failed + 1))
done

echo
if [ $failed -eq 0 ]; then
  echo -e "${GREEN}All ${#SUITES[@]} suites passed.${NC}"
else
  echo -e "${RED}${failed}/${#SUITES[@]} suites failed.${NC}"
fi
exit $failed
