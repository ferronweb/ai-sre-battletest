#!/usr/bin/env bash
# gray-failure.sh — Scenario: One route fails while health check stays green
#
# Injects a failure on /error?pct=1.0 on one backend while /health stays green.
# The aggregate error rate barely moves. Tests whether the agent finds the
# specific failing route rather than stopping at the top-level dashboard.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Gray Failure Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 5 "/"

echo "3. Injecting gray failure on backend-1..."
cat > /tmp/gray-failure-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=1.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF

docker compose ${COMPOSE_ALL} -f "/tmp/gray-failure-override.yml" up -d backend-1
wait_for_healthy backend-1 10 2 || true

echo "4. Running traffic against error route (30s)..."
run_loadgen 30 10 "/error" "GET" "HEADERS=X-Chaos:gray-failure"

echo "5. Running health check traffic (should be green)..."
run_loadgen 10 5 "/health"

echo "6. Restoring backend-1..."
docker compose ${COMPOSE_ALL} up -d backend-1
wait_for_healthy backend-1 10 2 || true
rm -f /tmp/gray-failure-override.yml

echo "=== Gray Failure Scenario Complete ==="
echo "Expected findings:"
echo "  - /health always returns 200"
echo "  - /error returns 500 on ~33% of requests (1 out of 3 backends)"
echo "  - Trace IDs from failed requests point to backend-1"
