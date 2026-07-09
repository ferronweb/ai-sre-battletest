#!/usr/bin/env bash
# missing-dependency-reload.sh — Scenario: Referenced upstream becomes unavailable after config reload
#
# Configures Ferron with a backend that exists, then removes that backend
# from Docker and triggers a reload. Tests whether Ferron's error surface
# (logs, admin API, exit behavior) makes "waiting on resource X that doesn't
# exist" as legible as kubectl describe pod does for CrashLoopBackOff.
#
# Simulates the K8s ingress controller scenario where a referenced Service
# or TLS Secret gets deleted out from under Ferron.
#
# Ferron3 only — tests reload behavior and error surfacing.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Missing Dependency Reload Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (tests admin API reload)"
    exit 0
fi

echo "1. Ensuring stack is up (including backend-4)..."
compose up -d
# Also start a 4th backend that we'll later remove
docker compose ${COMPOSE_ALL} run -d --rm --name backend-4 \
    -e LATENCY_MS=0 -e ERROR_PCT=0.0 -e ERROR_CODE=500 \
    -e TRACE_CORRUPT_PCT=0.0 -e HEALTHY=true \
    --network web \
    battletest-backend 2>/dev/null || true
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with 4 backends (including the one we'll remove)..."
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
        upstream http://backend-4:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Running baseline traffic with all 4 backends (20s)..."
run_loadgen 20 10 "/"

echo "4. Recording reload state before removal..."
RELOAD_BEFORE=$(curl -s http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Reload state: ${RELOAD_BEFORE}"

echo "5. Stopping and removing backend-4..."
docker compose ${COMPOSE_ALL} stop backend-4 2>/dev/null || true
docker compose ${COMPOSE_ALL} rm -f backend-4 2>/dev/null || true
sleep 2

echo "6. Triggering reload (Ferron will try to resolve backend-4)..."
RELOAD_RESULT=$(curl -s -X POST http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Reload result: ${RELOAD_RESULT}"
sleep 3

echo "7. Checking if Ferron is still healthy..."
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health 2>/dev/null || echo "000")
echo "   Health: ${HEALTH}"

echo "8. Checking reload status for errors..."
RELOAD_AFTER=$(curl -s http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Reload state after: ${RELOAD_AFTER}"

echo "9. Running traffic after dependency removal (30s)..."
run_loadgen 30 15 "/"

echo "10. Checking active connections and status..."
STATUS=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
echo "   Status: ${STATUS}"

echo "11. Restoring backend-4 and default config..."
docker compose ${COMPOSE_ALL} run -d --rm --name backend-4 \
    -e LATENCY_MS=0 -e ERROR_PCT=0.0 -e ERROR_CODE=500 \
    -e TRACE_CORRUPT_PCT=0.0 -e HEALTHY=true \
    --network web \
    battletest-backend 2>/dev/null || true
sleep 3

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

echo "=== Missing Dependency Reload Scenario Complete ==="
echo "Expected findings:"
echo "  - Ferron config references backend-4 which is then removed"
echo "  - After reload: Ferron may log errors about unreachable upstream"
echo "  - GET /reload may show last_reload_error with details"
echo "  - Ferron should stay healthy and serve traffic to remaining 3 backends"
echo "  - Agent must distinguish 'one backend missing' from 'all backends down'"
echo "  - In K8s context: missing Secret/Service should produce clear error messages"
