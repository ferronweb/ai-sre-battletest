#!/usr/bin/env bash
# retry-idempotency-hazard.sh — Scenario: POST retry causes duplicate processing
#
# Configures retry_connection with a backend that accepts POST requests but
# responds slowly. If the response arrives after Ferron's timeout, does Ferron
# retry the POST to another backend? If so, a payment-like endpoint gets
# double-processed.
#
# Uses the /post-count endpoint which atomically increments a counter on each
# POST. If the counter exceeds the number of distinct requests, duplicates
# occurred.
#
# Distinct from retry-amplification.sh (which tests volume amplification on
# GET). This tests retry correctness on non-idempotent methods.
#
# Ferron3 only — tests retry behavior and POST safety.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Retry Idempotency Hazard Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (tests Ferron retry behavior)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with retry_connection enabled..."
cat > docker/config/ferron3/ferron.conf << 'FERRONEOF'
{
    admin { listen "0.0.0.0:8081" }
    observability {
        provider otlp
        logs http://otel-collector:4317/v1/logs
        metrics http://otel-collector:4317/v1/metrics
        traces http://otel-collector:4317/v1/traces
    }
}
*:80 {
    proxy {
        algorithm round_robin
        retry_connection true
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Injecting 10s latency on backend-1 (POST takes too long, triggers timeout)..."
cat > /tmp/idempotency-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=10000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF
docker compose ${COMPOSE_ALL} -f /tmp/idempotency-override.yml up -d backend-1
wait_for_healthy backend-1 10 2 || true

echo "4. Sending 5 POST requests with 3s client timeout (backend-1 takes 10s)..."
# Client timeout 3s < backend latency 10s → client times out, Ferron may retry
# Use low rate and short duration to avoid timeout issues
run_loadgen 15 1 "/post-count" "POST" "TIMEOUT_SECS=3" "CONCURRENCY=1" "BODY_SIZE=64" "HEADERS=X-Chaos:idempotency-test"

echo "5. Checking POST count on all backends (via proxy)..."
# Each backend has its own counter. We send 5 requests via proxy.
# If Ferron retries POSTs, the total across backends will exceed 5.
# Note: in round-robin, requests are distributed, so individual counts
# may be low. The key metric is ferron.proxy.retry.count.
TOTAL_POSTS=0
for i in 1 2 3; do
    RESP=$(curl -s -X POST "http://localhost:80/post-count" -d "check" 2>/dev/null || echo "error")
    COUNT=$(echo "${RESP}" | grep -o 'post_count:[0-9]*' | cut -d: -f2 || echo "0")
    echo "   backend-${i} responded: ${RESP}"
    TOTAL_POSTS=$((TOTAL_POSTS + ${COUNT:-0}))
done
echo "   Total POST count across all backends: ${TOTAL_POSTS} (expected: 5 if no duplicates, >5 if retries occurred)"

echo "6. Querying admin API for retry metrics..."
STATUS=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
echo "   Status: ${STATUS}"

echo "7. Restoring configuration..."
docker compose ${COMPOSE_ALL} up -d backend-1
wait_for_healthy backend-1 10 2 || true

cat > docker/config/ferron3/ferron.conf << 'FERRONEOF'
{
    admin { listen "0.0.0.0:8081" }
    observability {
        provider otlp
        logs http://otel-collector:4317/v1/logs
        metrics http://otel-collector:4317/v1/metrics
        traces http://otel-collector:4317/v1/traces
    }
}
*:80 {
    proxy {
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true
rm -f /tmp/idempotency-override.yml

echo "=== Retry Idempotency Hazard Scenario Complete ==="
echo "Expected findings:"
echo "  - POST to backend-1 times out (10s latency > 3s client timeout)"
echo "  - If retry_connection resends POST: post_count across backends > 10 (duplicates)"
echo "  - If Ferron correctly skips POST retries: post_count == 10 (no duplicates)"
echo "  - Agent must check whether retries are restricted to idempotent methods"
echo "  - Ferron proxy.retry.count metric shows retry attempts"
echo "  - Trace spans show retry_count attribute on retried requests"
