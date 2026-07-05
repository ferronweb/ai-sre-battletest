#!/usr/bin/env bash
# health-check-manipulation.sh — Proxy health check probes wrong path; backend stays in rotation
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Health Check Manipulation Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 10 "/"

echo "3. Writing proxy-level health check config (probes / instead of /health)..."
if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /etc/traefik/dynamic/health-check.yml" << 'EOF'
http:
  services:
    api:
      loadBalancer:
        healthCheck:
          path: /
          interval: 10s
          timeout: 5s
        servers:
          - url: "http://backend-1:3000"
          - url: "http://backend-2:3000"
          - url: "http://backend-3:3000"
EOF
else
    cat > /tmp/ferron3-hc.conf << 'FERRONEOF'
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
        upstream http://backend-1:3000 {
            active_check {
                uri "/"
                interval "10s"
                timeout "5s"
                consecutive_fails 2
                consecutive_passes 2
            }
        }
        upstream http://backend-2:3000 {
            active_check {
                uri "/"
                interval "10s"
                timeout "5s"
                consecutive_fails 2
                consecutive_passes 2
            }
        }
        upstream http://backend-3:3000 {
            active_check {
                uri "/"
                interval "10s"
                timeout "5s"
                consecutive_fails 2
                consecutive_passes 2
            }
        }
    }
}
FERRONEOF
    cp /tmp/ferron3-hc.conf docker/config/ferron3/ferron.conf
    docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
    wait_for_healthy proxy 10 2 || true
fi

echo "4. Injecting health check mismatch on backend-1..."
cat > /tmp/health-check-override.yml << EOF
services:
  backend-1:
    environment:
      - LATENCY_MS=0
      - ERROR_PCT=0.4
      - ERROR_CODE=503
      - TRACE_CORRUPT_PCT=0.0
      - HEALTHY=false
EOF
docker compose ${COMPOSE_ALL} -f /tmp/health-check-override.yml up -d backend-1
wait_for_healthy backend-1 10 2 || true

echo "5. Running traffic against /stream/10000 (long-lived connections) (60s)..."
run_loadgen 60 10 "/stream/10000" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=30" "HEADERS=X-Chaos:health-check-manipulation"

echo "6. Restoring backend-1 and proxy config..."
docker compose ${COMPOSE_ALL} up -d backend-1
wait_for_healthy backend-1 10 2 || true

if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "rm -f /etc/traefik/dynamic/health-check.yml"
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

rm -f /tmp/health-check-override.yml /tmp/ferron3-hc.conf

echo "=== Health Check Manipulation Scenario Complete ==="
echo "Expected: proxy marks backend healthy while /health returns 503"
