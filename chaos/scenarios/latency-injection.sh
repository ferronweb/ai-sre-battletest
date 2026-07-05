#!/usr/bin/env bash
# latency-injection.sh — Scenario: Inject 2-5s delay on backend responses
#
# Adds latency to backend-1 and backend-2 responses without failing them.
# Circuit breaker (keyed on error rate) won't trip. p50 stays fine, p99
# explodes, queues build silently. Tests whether the agent looks at
# percentiles vs averages and whether queue depth is surfaced.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Latency Injection Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic to measure p50/p99..."
run_loadgen 30 20 "/"

echo "3. Injecting 3s latency on backend-1 and backend-2..."
cat > /tmp/latency-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=3000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-2:
    environment:
      - LATENCY_MS=3000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF

docker compose ${COMPOSE_ALL} -f "/tmp/latency-override.yml" up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true

echo "4. Running traffic during latency injection (60s)..."
run_loadgen 60 20 "/"

echo "5. Restoring backends..."
docker compose ${COMPOSE_ALL} up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true
rm -f /tmp/latency-override.yml

echo "=== Latency Injection Scenario Complete ==="
echo "Expected findings:"
echo "  - /health stays green"
echo "  - p99 latency spikes to ~3s while p50 stays near-normal"
echo "  - No errors/5xx (circuit breaker doesn't trip on latency alone)"
echo "  - Backend-3 has normal latency"
