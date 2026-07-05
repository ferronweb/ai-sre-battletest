#!/usr/bin/env bash
# mtls-ca-missing.sh — Scenario: mTLS CA file path wrong, all connections rejected
#
# Enables client_auth but points to wrong CA file path.
# ALL client connections fail with TLS handshake error.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== mTLS CA File Missing Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with mTLS (wrong CA path)..."
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
*:443 {
    host {
        server_name "localhost"
        tls {
            certificate_file "/etc/ferron/tls/server.crt"
            private_key_file "/etc/ferron/tls/server.key"
            client_auth true
            client_auth_ca_file "/etc/ferron/tls/wrong-ca.crt"
        }
    }
    proxy {
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
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

echo "4. Running traffic — ALL connections should fail (60s)..."
run_loadgen 60 50 "/"

echo "5. Restoring default Ferron3 config..."
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

echo "=== mTLS CA File Missing Scenario Complete ==="
echo "Expected findings:"
echo "  - 100% connection failures (TLS handshake errors)"
echo "  - Looks like a network issue, but it's a misconfigured CA path"
echo "  - Agent must check TLS handshake errors in logs"
echo "  - Agent must distinguish mTLS failure from network outage"
