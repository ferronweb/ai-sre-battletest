#!/usr/bin/env bash
# basic-auth-concurrency.sh — Scenario: Concurrency limit locks out legitimate users
#
# Configures basic auth with concurrency_limit=10, then sends 50 concurrent users.
# Only 10 succeed, rest get 403.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Basic Auth Concurrency Lockout Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with basic auth (concurrency_limit=10)..."
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
    basic_auth {
        credentials {
            user1 "$apr1$xyz$hashedpassword"
        }
        realm "Restricted Area"
        concurrency_limit 10
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

echo "4. Running traffic with auth headers (30s)..."
run_loadgen 30 20 "/" "GET" "HEADERS=Authorization:Basic dXNlcjE6cGFzc3dvcmQx"

echo "5. Simulating 50 concurrent users behind NAT..."
for i in $(seq 1 50); do
    curl -s -o /dev/null -w "%{http_code} " -H "Authorization: Basic dXNlcjE6cGFzc3dvcmQx" "http://localhost:80/" &
done
wait
echo ""

echo "6. Running aggressive concurrent traffic (60s)..."
run_loadgen 60 50 "/" "GET" "HEADERS=Authorization:Basic dXNlcjE6cGFzc3dvcmQx"

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

echo "=== Basic Auth Concurrency Lockout Scenario Complete ==="
echo "Expected findings:"
echo "  - Only 10 concurrent connections succeed"
echo "  - Rest get 403 (concurrency limit exceeded)"
echo "  - Agent must check concurrency state, not just brute-force protection"
echo "  - Legitimate users sharing an IP get locked out"
