#!/usr/bin/env bash
# rate-limit-burst.sh — Scenario: SPA burst loading triggers rate limits
#
# Configures rate limiting with low burst, then simulates SPA loading.
# Rapid asset requests trigger 429s, breaking pages.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Rate Limit Burst Mismatch Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with rate limiting (burst=5)..."
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
    rate_limit {
        enabled true
        zone static_zone {
            key http_remote_addr
            rate_limit 10r/s
            burst 5
            rate_limit_status 429
            rate_limit_headers true
        }
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

echo "4. Running normal browsing traffic (30s)..."
run_loadgen 30 20 "/"

echo "5. Simulating SPA burst loading — 30 assets in rapid succession..."
for asset in $(seq 1 30); do
    curl -s -o /dev/null -w "%{http_code} " "http://localhost:80/?asset=${asset}" &
done
wait
echo ""

echo "6. Running aggressive burst traffic (60s)..."
run_loadgen 60 100 "/"

echo "7. Restoring default Ferron3 config..."
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

echo "=== Rate Limit Burst Mismatch Scenario Complete ==="
echo "Expected findings:"
echo "  - 429 responses during SPA burst and aggressive traffic"
echo "  - Rate limit headers (X-RateLimit-*) visible in 429 responses"
echo "  - Agent must correlate 429s with burst config, not just rate"
echo "  - Legitimate SPA loading triggers rate limit due to low burst"
