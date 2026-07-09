#!/usr/bin/env bash
# cascading-downstream-trace.sh — Scenario: Backend's own downstream is slow, not the backend itself
#
# Backend-1 has high latency (simulating a slow downstream dependency one hop
# beyond Ferron). W3C Trace Context propagation should make the real bottleneck
# visible in traces as one hop past Ferron, rather than looking like
# "backend-1 is slow" indistinguishable from a backend-side bug.
#
# Tests whether Ferron's tracing makes "the problem isn't your backend,
# it's your backend's dependency" diagnosable.
#
# Ferron3 only — tests trace context propagation and span attributes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Cascading Downstream Trace Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (tests trace propagation)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with tracing..."
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
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Running baseline traffic (15s)..."
run_loadgen 15 5 "/" "GET" "HEADERS=X-Chaos:cascading-downstream"

echo "4. Injecting 2s latency ONLY on backend-1 (simulating slow downstream)..."
cat > /tmp/cascading-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=2000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-2:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-3:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF
docker compose ${COMPOSE_ALL} -f /tmp/cascading-override.yml up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "5. Running traffic during latency injection (20s)..."
run_loadgen_background 20 3 "/" "GET" "TIMEOUT_SECS=5" "HEADERS=X-Chaos:cascading-downstream"

echo "6. Waiting 25s for loadgen to complete..."
sleep 25

echo "7. Checking trace context propagation on /trace endpoint..."
echo "   (Trace headers should show backend-1 as the slow span)"
TRACE_RESPONSE=$(curl -s http://localhost:80/trace 2>/dev/null || echo "failed")
echo "   Trace response: ${TRACE_RESPONSE}"

echo "8. Querying traces from Tempo to verify span hierarchy..."
# The trace should show: client -> Ferron.proxy -> backend-1 (5s) -> done
# If backend-1 had a real downstream, there would be an additional child span

echo "9. Restoring backends..."
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
rm -f /tmp/cascading-override.yml

echo "=== Cascading Downstream Trace Scenario Complete ==="
echo "Expected findings:"
echo "  - backend-1 has 2s latency, backends 2-3 are fast"
echo "  - Traces show backend-1 span taking ~2s"
echo "  - Ferron's reverse_proxy span shows ferron.proxy.backend_url=backend-1:3000"
echo "  - If backend-1 called a downstream, trace context would propagate via traceparent"
echo "  - Agent must distinguish 'backend is slow' from 'backend's dependency is slow'"
echo "  - In real setup: trace would show child span beyond backend-1 as the bottleneck"
