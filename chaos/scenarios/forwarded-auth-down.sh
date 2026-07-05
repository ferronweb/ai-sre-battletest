#!/usr/bin/env bash
# forwarded-auth-down.sh — Scenario: Auth backend unreachable, all requests fail
#
# Configures Ferron3 forwarded_auth, then stops the auth backend.
# All requests fail with no fallback authentication.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Forwarded Auth Backend Down Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up (including auth-backend)..."
compose up -d
compose_chaos up -d auth-backend
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done
wait_for_healthy auth-backend 10 2 || true

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with forwarded auth..."
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
    forwarded_auth auth_backend {
        server "auth-backend:8080"
        path "/auth"
        method GET
        timeout 5
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

echo "4. Running traffic with auth backend up (30s)..."
run_loadgen 30 50 "/"

echo "5. Stopping auth backend..."
compose_chaos stop auth-backend
sleep 2

echo "6. Running traffic with auth backend down (60s) — ALL should fail..."
run_loadgen 60 50 "/"

echo "7. Starting auth backend..."
compose_chaos start auth-backend
wait_for_healthy auth-backend 10 2 || true

echo "8. Running traffic after recovery (30s)..."
run_loadgen 30 50 "/"

echo "9. Restoring default Ferron3 config..."
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
compose_chaos stop auth-backend 2>/dev/null || true

echo "=== Forwarded Auth Backend Down Scenario Complete ==="
echo "Expected findings:"
echo "  - Complete outage when auth backend is down"
echo "  - No fallback authentication mechanism"
echo "  - Agent must check both Ferron3 and auth-backend"
echo "  - Recovery is immediate after auth backend restarts"
