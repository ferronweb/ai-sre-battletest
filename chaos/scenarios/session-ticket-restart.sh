#!/usr/bin/env bash
# session-ticket-restart.sh — Scenario: Session ticket keys lost on restart
#
# Restarts Ferron3, losing auto-rotated TLS session ticket keys.
# All clients must do full TLS handshake, causing latency spike.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Session Ticket Key Loss Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with TLS..."
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

echo "3. Running baseline traffic to establish TLS sessions (30s)..."
run_loadgen 30 50 "/"

echo "4. Restarting Ferron3 (loses session ticket keys)..."
docker compose ${COMPOSE_ALL} restart proxy
sleep 5
wait_for_healthy proxy 10 2 || true

echo "5. Running traffic after restart (60s) — full TLS handshakes..."
run_loadgen 60 50 "/"

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

echo "=== Session Ticket Key Loss Scenario Complete ==="
echo "Expected findings:"
echo "  - Latency spike immediately after Ferron3 restart"
echo "  - All clients do full TLS handshake (no session ticket reuse)"
echo "  - Gradual recovery as new session tickets are issued"
echo "  - Agent must correlate latency spike with restart event"
