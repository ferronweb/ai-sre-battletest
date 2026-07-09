#!/usr/bin/env bash
# dns-record-change.sh — Scenario: Backend container recreated with new IP mid-traffic
#
# Stops backend-1 and restarts it (getting a new Docker IP). Tests whether
# Ferron's STRICT_DNS + per-IP circuit breaker correctly detects the change
# and re-resolves, versus continuing to hammer a dead IP on a stale cache.
#
# Uses ferron.proxy.dns.cache_hit/miss metrics and per-IP breaker state.
# Validates the STRICT_DNS design choice.
#
# Ferron3 only — tests DNS cache metrics and per-IP circuit breaker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== DNS Record Change Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (tests DNS cache metrics)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with metrics_resolved_ip for per-IP visibility..."
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
        metrics_resolved_ip true
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Running baseline traffic to populate DNS cache (30s)..."
run_loadgen 30 20 "/"

echo "4. Recording backend-1's current IP..."
BACKEND1_IP=$(docker compose ${COMPOSE_ALL} exec -T backend-1 hostname -i 2>/dev/null | tr -d '\r' || echo "unknown")
echo "   backend-1 IP: ${BACKEND1_IP}"

echo "5. Checking baseline DNS cache metrics..."
STATUS_BASELINE=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
echo "   Baseline status: ${STATUS_BASELINE}"

echo "6. Stopping backend-1 (simulating container recreation)..."
stop_backend backend-1
sleep 2

echo "7. Restarting backend-1 (gets new Docker IP)..."
start_backend backend-1
wait_for_healthy backend-1 15 2 || true

echo "8. Recording new backend-1 IP..."
BACKEND1_IP_NEW=$(docker compose ${COMPOSE_ALL} exec -T backend-1 hostname -i 2>/dev/null | tr -d '\r' || echo "unknown")
echo "   backend-1 new IP: ${BACKEND1_IP_NEW}"

echo "9. Running traffic during DNS re-resolution window (30s)..."
run_loadgen 30 20 "/"

echo "10. Checking DNS cache metrics after IP change..."
STATUS_POST=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
echo "   Post-change status: ${STATUS_POST}"

echo "11. Running recovery traffic (20s)..."
run_loadgen 20 10 "/"

echo "12. Restoring default config..."
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

echo "=== DNS Record Change Scenario Complete ==="
echo "Expected findings:"
echo "  - Backend-1 gets a new IP after restart (${BACKEND1_IP} -> ${BACKEND1_IP_NEW})"
echo "  - ferron.proxy.dns.cache_miss should increment during re-resolution"
echo "  - Ferron should detect new IP and add it to the load balancer pool"
echo "  - Old IP may briefly cause connection failures before detection"
echo "  - Per-IP circuit breaker state shows old IP as unhealthy"
echo "  - metrics_resolved_ip shows distinct metrics per resolved IP"
echo "  - Agent must correlate DNS change with temporary errors"
