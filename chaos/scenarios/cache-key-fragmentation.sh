#!/usr/bin/env bash
# cache-key-fragmentation.sh — Scenario: Cookies fragment cache keys, hit rate drops
#
# Enables cache with include cookies true, then sends diverse cookies.
# Cache fragments, hit rate drops dramatically.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Cache Key Fragmentation Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with cache (include cookies true)..."
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
        default_max_age 60
        include cookies true
        include vary true
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

echo "3. Running baseline traffic with fixed cookies (30s)..."
run_loadgen 30 50 "/"

echo "4. Running traffic with diverse cookies — cache fragmentation (60s)..."
# Each request gets a unique cookie pair, fragmenting the cache
for i in $(seq 1 60); do
    curl -s -o /dev/null -H "Cookie: session=user-${RANDOM}-${RANDOM}" "http://localhost:80/" &
    if [ $((i % 10)) -eq 0 ]; then
        sleep 1
    fi
done
wait

echo "5. Running traffic with fixed cookies again (30s)..."
run_loadgen 30 50 "/"

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

echo "=== Cache Key Fragmentation Scenario Complete ==="
echo "Expected findings:"
echo "  - Cache hit rate drops from ~95% to ~10% with diverse cookies"
echo "  - Backend request rate increases proportionally"
echo "  - p50 latency increases slightly due to cache misses"
echo "  - Agent must check cache configuration, not just backend health"
