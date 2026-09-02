#!/usr/bin/env bash
# Posts a "resilience testing" annotation to Grafana. The chaos suites call this to mark the
# start and stop of each disruption on the dashboard.
#
# Annotations are cosmetic. An unreachable Grafana -- no port-forward, or not installed at all --
# therefore only warns and must not fail a chaos test that otherwise passed. Set
# GRAFANA_STRICT=true to turn that back into a hard failure.
set -euo pipefail

GRAFANA_URL=http://localhost:3000
GRAFANA_STRICT="${GRAFANA_STRICT:-false}"

YELLOW='\033[1;33m'
NC='\033[0m'

TEXT="${1:?Missing annotation text}"

TIMESTAMP_MS=$(($(date +%s) * 1000))

# -f so that an HTTP 401/404 counts as a failure instead of being silently discarded, and
# --max-time so a missing port-forward fails in seconds rather than hanging the test.
if curl -fsS --max-time 5 -X POST "${GRAFANA_URL}/api/annotations" \
  --user admin:admin \
  -H "Content-Type: application/json" \
  -d "{
    \"time\": ${TIMESTAMP_MS},
    \"tags\": [\"resilience testing\"],
    \"text\": \"${TEXT}\"
  }" >/dev/null; then
  echo "Annotated Grafana: ${TEXT}"
  exit 0
fi

echo -e "${YELLOW}Warning: could not annotate Grafana at ${GRAFANA_URL} (\"${TEXT}\")${NC}" >&2
echo "To get annotations, port-forward Grafana:" >&2
echo "  kubectl --context kind-zurich -n monitoring port-forward svc/prom-grafana 3000:80" >&2

if [[ "$GRAFANA_STRICT" == "true" ]]; then
  exit 1
fi
# Explicit, otherwise the script would exit with the status of the test above.
exit 0
