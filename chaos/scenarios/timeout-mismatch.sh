#!/usr/bin/env bash
# timeout-mismatch.sh — Scenario: Client timeout < proxy timeout < backend timeout
#
# Deliberately misconfigures timeouts so that:
#   Client (loadgen) timeout < Proxy timeout < Backend /slow duration
# Client retries while the proxy is still waiting on the abandoned backend call,
# doubling load for no visible reason in any single layer's logs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Timeout Mismatch Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Injecting 10s latency on all backends (backend timeout > proxy timeout)..."
cat > /tmp/timeout-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=10000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-2:
    environment:
      - LATENCY_MS=10000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
  backend-3:
    environment:
      - LATENCY_MS=10000
      - ERROR_PCT=0.0
      - ERROR_CODE=500
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=true
EOF

docker compose ${COMPOSE_ALL} -f "/tmp/timeout-override.yml" up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

if [ "${PROXY}" = "traefik" ]; then
    echo "3. Setting proxy timeout to 3s (via file provider dynamic config)..."
    compose exec -T proxy mkdir -p /etc/traefik/dynamic
    compose exec -T proxy sh -c 'cat > /etc/traefik/dynamic/timeout.yml << EOF
http:
  serversTransports:
    default:
      forwardTimeout: 3s
EOF'
    echo "   Traefik file provider watches /etc/traefik/dynamic — config will be picked up automatically."
    sleep 2
elif [ "${PROXY}" = "ferron3" ]; then
    echo "3. Setting proxy timeout to 3s in ferron.conf..."
    compose exec -T proxy sh -c 'cat > /etc/ferron/ferron.conf << EOF
{
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
        connect_timeout 3s
        read_timeout 3s
    }
}
EOF'
    compose restart proxy
    sleep 3
fi

echo "4. Running traffic with short client timeout (1s) + retries..."
# Client timeout 1s, hitting /slow/5000 (5s) -> client times out and retries
# Proxy has 3s timeout -> proxy also times out
# Backend eventually responds after 10s but nobody is listening
run_loadgen 30 15 "/slow/5000" "GET" "TIMEOUT_SECS=1"

echo "5. Restoring configuration..."
docker compose ${COMPOSE_ALL} up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

if [ "${PROXY}" = "traefik" ]; then
    compose exec -T proxy rm -f /etc/traefik/dynamic/timeout.yml 2>/dev/null || true
    compose restart proxy
elif [ "${PROXY}" = "ferron3" ]; then
    compose restart proxy
fi
rm -f /tmp/timeout-override.yml

echo "=== Timeout Mismatch Scenario Complete ==="
echo "Expected findings:"
echo "  - Loadgen sees connection timeouts (~1s)"
echo "  - Loadgen retries, doubling effective request rate at the proxy"
echo "  - Proxy sees connections opened and then abandoned"
echo "  - Backend eventually responds but response is discarded"
echo "  - No single layer has a complete picture — need to compare all three"
