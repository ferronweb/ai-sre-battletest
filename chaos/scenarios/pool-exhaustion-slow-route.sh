#!/usr/bin/env bash
# pool-exhaustion-slow-route.sh — Scenario: Slow route starves connection pool for fast routes
#
# Configures a low per-upstream connection limit. Sends /stream/{ms} requests
# that hold connections open for a long time under high concurrency, starving
# the pool for unrelated fast routes hitting the same backend.
#
# Tests whether ferron_proxy_pool.waits, pool.wait_time, and pool.outstanding
# make the "healthy backend, exhausted pool" distinction obvious, and whether
# pool sizing config is discoverable via admin API.
#
# Ferron3 only — tests admin API metrics and pool configuration.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Pool Exhaustion Slow Route Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (requires admin API pool metrics)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with low connection pool limit..."
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
        upstream http://backend-1:3000 {
            limit 5
            idle_timeout "30s"
        }
        upstream http://backend-2:3000 {
            limit 5
            idle_timeout "30s"
        }
        upstream http://backend-3:3000 {
            limit 5
            idle_timeout "30s"
        }
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Running baseline traffic to warm pool (20s)..."
run_loadgen 20 10 "/"

echo "4. Checking baseline pool config via admin API..."
CONFIG=$(curl -s http://localhost:8081/config 2>/dev/null || echo "{}")
echo "   Config endpoint available: $(echo "${CONFIG}" | wc -c) bytes"

echo "5. Starting slow requests on backend-1 (holding connections open)..."
# 5 slow streams × concurrency 50 = 250 concurrent connections, but pool limit is 5 per upstream
run_loadgen_background 60 5 "/stream/30000" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=60" "HEADERS=X-Chaos:pool-slow"

echo "6. Waiting 15s for pool to saturate..."
sleep 15

echo "7. Running fast requests while pool is exhausted (30s)..."
run_loadgen_background 30 20 "/" "GET" "HEADERS=X-Chaos:pool-fast"

echo "8. Waiting 35s for fast loadgen to complete..."
sleep 35

echo "9. Checking admin API status during exhaustion..."
STATUS=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
ACTIVE=$(echo "${STATUS}" | grep -o '"connections_active":[0-9]*' | cut -d: -f2 || echo "0")
echo "   Active connections: ${ACTIVE}"

echo "9. Waiting for slow streams to finish..."
sleep 45

echo "10. Restoring default Ferron3 config..."
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

echo "=== Pool Exhaustion Slow Route Scenario Complete ==="
echo "Expected findings:"
echo "  - Slow /stream requests hold connections open, exhausting pool limit (5)"
echo "  - Fast / requests to same backends experience pool waits"
echo "  - ferron_proxy.pool.waits should increment for fast routes"
echo "  - ferron_proxy.pool.wait_time histogram shows wait durations"
echo "  - ferron_proxy.pool.outstanding shows connection saturation"
echo "  - Admin API /config reveals pool limit (limit 5 per upstream)"
echo "  - Backend health stays green — the issue is pool starvation, not backend failure"
