#!/usr/bin/env bash
# cache-poisoning.sh — Scenario: Backend returns wrong Cache-Control, errors get cached
#
# Backend returns errors with long Cache-Control headers.
# Cache stores the error response, serving it even after backend recovers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Cache Poisoning Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with cache enabled..."
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
        include cache_control true
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

echo "3. Running baseline traffic (30s)..."
run_loadgen 30 50 "/"

echo "4. Injecting errors on backend-1 with poisoned cache headers..."
cat > /tmp/cache-poisoning-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=1.0
      - ERROR_CODE=502
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF
docker compose ${COMPOSE_ALL} -f "/tmp/cache-poisoning-override.yml" up -d backend-1
wait_for_healthy backend-1 10 2 || true

echo "5. Running traffic during poisoning (60s) — errors get cached..."
run_loadgen 60 50 "/"

echo "6. Recovering backend-1 — cached errors should persist..."
docker compose ${COMPOSE_ALL} up -d backend-1
wait_for_healthy backend-1 10 2 || true

echo "7. Running traffic after recovery (60s) — cached errors still served..."
run_loadgen 60 50 "/"

echo "8. Restoring default Ferron3 config..."
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
rm -f /tmp/cache-poisoning-override.yml

echo "=== Cache Poisoning Scenario Complete ==="
echo "Expected findings:"
echo "  - Cache hit rate stays high (cache is working)"
echo "  - But error rate also stays high (cached errors)"
echo "  - After backend-1 recovery, errors persist for cache TTL duration"
echo "  - Agent must notice that errors are being cached"
