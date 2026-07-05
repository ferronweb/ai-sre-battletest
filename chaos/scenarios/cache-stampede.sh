#!/usr/bin/env bash
# cache-stampede.sh — Scenario: Cache expires simultaneously, thundering herd hits backend
#
# Enables cache with short max_age, populates cache, waits for expiry,
# then launches multiple loadgen instances simultaneously.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Cache Stampede Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with short cache TTL..."
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
    cache {
        enabled true
        default_max_age 5
        include cache_control false
        include vary false
        include content_encoding false
        include content_length false
        include cookies false
    }
    proxy {
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
wait_for_healthy proxy 10 2 || true

echo "3. Running baseline traffic to populate cache (30s)..."
run_loadgen 30 50 "/"

echo "4. Waiting for cache to expire (8s)..."
sleep 8

echo "5. Launching simultaneous traffic — cache stampede (60s)..."
# Three loadgen instances hitting the same URL simultaneously
run_loadgen_background 60 100 "/" "GET" "HEADERS=X-Chaos:stampede-1"
run_loadgen_background 60 100 "/" "GET" "HEADERS=X-Chaos:stampede-2"
run_loadgen_background 60 100 "/" "GET" "HEADERS=X-Chaos:stampede-3"
sleep 60

echo "6. Restoring default Ferron3 config..."
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

echo "=== Cache Stampede Scenario Complete ==="
echo "Expected findings:"
echo "  - Cache expires simultaneously for all keys"
echo "  - Backend request rate spikes from ~50/s to ~300/s"
echo "  - Backend CPU spikes during stampede"
echo "  - p99 latency spikes while p50 stays normal"
echo "  - No errors (backend handles load, just slowly)"
