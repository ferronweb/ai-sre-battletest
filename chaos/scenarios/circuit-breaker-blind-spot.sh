#!/usr/bin/env bash
# circuit-breaker-blind-spot.sh — Extreme latency with no errors — circuit breaker doesn't trip
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Circuit Breaker Blind Spot Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 10 "/"

echo "3. Writing proxy-level circuit breaker config..."
if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /etc/traefik/dynamic/circuit-breaker.yml" << 'EOF'
http:
  middlewares:
    cb-test:
      circuitBreaker:
        expression: "NetworkErrorRatio() > 0.50"
        checkPeriod: 1s
        fallbackDuration: 10s
        recoveryDuration: 10s
  routers:
    api:
      middlewares:
        - cb-test
EOF
else
    cat > /tmp/ferron3-cb.conf << 'FERRONEOF'
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
        circuit_breaker {
            max_fails 5
            window "30s"
            open_duration "10s"
            consecutive_passes 1
            record_5xx true
        }
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF
    cp /tmp/ferron3-cb.conf docker/config/ferron3/ferron.conf
    docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
    wait_for_healthy proxy 10 2 || true
fi

echo "4. Injecting 5s latency on backend-1 and backend-2 (no errors)..."
cat > /tmp/circuit-breaker-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=5000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-2:
    environment:
      - LATENCY_MS=5000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF
docker compose ${COMPOSE_ALL} -f /tmp/circuit-breaker-override.yml up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true

echo "5. Running traffic during latency injection (60s)..."
run_loadgen 60 10 "/stream/10000" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=30" "HEADERS=X-Chaos:circuit-breaker-blind-spot"

echo "6. Restoring backends and proxy config..."
docker compose ${COMPOSE_ALL} up -d backend-1 backend-2
wait_for_healthy backend-1 10 2 || true
wait_for_healthy backend-2 10 2 || true

if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "rm -f /etc/traefik/dynamic/circuit-breaker.yml"
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

rm -f /tmp/circuit-breaker-override.yml /tmp/ferron3-cb.conf

echo "=== Circuit Breaker Blind Spot Scenario Complete ==="
echo "Expected: circuit breaker stays closed, p99 ~5s, 0% errors"
