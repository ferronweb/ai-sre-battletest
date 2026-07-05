#!/usr/bin/env bash
# retry-amplification.sh — Scenario: Retry config on proxy amplifies backend errors into a storm
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Retry Amplification Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 10 "/"

echo "3. Writing proxy-level retry config..."
if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /etc/traefik/dynamic/retry.yml" << 'EOF'
http:
  middlewares:
    retry-test:
      retry:
        attempts: 4
        initialInterval: 200ms
        timeout: 30s
  routers:
    api:
      middlewares:
        - retry-test
EOF
else
    cat > /tmp/ferron3-retry.conf << 'FERRONEOF'
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
        retry_connection true
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
    cp /tmp/ferron3-retry.conf docker/config/ferron3/ferron.conf
    docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
    wait_for_healthy proxy 10 2 || true
fi

echo "4. Injecting intermittent 503 errors on backend-1 and backend-2..."
cat > /tmp/retry-amplification-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=0.3
      - ERROR_CODE=503
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-2:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=0.3
      - ERROR_CODE=503
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF
docker compose ${COMPOSE_ALL} -f /tmp/retry-amplification-override.yml up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true

echo "5. Running traffic during retry amplification (60s)..."
run_loadgen 60 10 "/stream/10000" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=30" "HEADERS=X-Chaos:retry-amplification"

echo "6. Restoring backends and proxy config..."
docker compose ${COMPOSE_ALL} up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true

if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "rm -f /etc/traefik/dynamic/retry.yml"
else
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
fi

rm -f /tmp/retry-amplification-override.yml /tmp/ferron3-retry.conf

echo "=== Retry Amplification Scenario Complete ==="
echo "Expected: proxy request rate 2-4x client rate due to retries"
