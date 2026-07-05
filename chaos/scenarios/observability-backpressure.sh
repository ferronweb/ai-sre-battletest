#!/usr/bin/env bash
# observability-backpressure.sh — Flood OTel Collector with high-cardinality spans
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Observability Backpressure Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Building trace-flood agent image..."
docker build -t trace-flood-agent "${SCRIPT_DIR}/../agents/trace-flood/"

echo "3. Running baseline traffic (30s)..."
run_loadgen 30 10 "/"

echo "4. Starting trace-flood agent (50k spans/s for 90s)..."
compose_chaos run -d --rm \
    -e SPAN_RATE=50000 \
    -e OTLP_ENDPOINT=http://otel-collector:4317 \
    -e DURATION_SECS=90 \
    -e CARDINALITY=20 \
    --name trace-flood-agent \
    trace-flood

echo "5. Running traffic during trace flood (60s)..."
run_loadgen 60 10 "/stream/10000" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=30" "HEADERS=X-Chaos:observability-backpressure"

echo "6. Checking OTel Collector for dropped spans..."
compose logs --tail=10 otel-collector 2>/dev/null || true

echo "7. Waiting for trace flood to complete..."
docker wait trace-flood-agent 2>/dev/null || true

echo "8. Verifying telemetry recovery..."
sleep 10
run_loadgen 10 5 "/health"

echo "=== Observability Backpressure Scenario Complete ==="
echo "Expected: Grafana gaps, OTel Collector drops spans, app stays healthy"
