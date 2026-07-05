#!/usr/bin/env bash
# forward-proxy-whitelist-bypass.sh — Scenario: Forward proxy bypasses abuse protection
#
# Configures Ferron3 with forward proxy and abuse protection.
# Attacker uses forward proxy to bypass IP-based bans.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Forward Proxy Whitelist Bypass Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with forward proxy and abuse protection..."
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
    forward_proxy {
        enabled true
        allowed_ports 80 443
    }
    rate_limit {
        enabled true
        zone api_zone {
            key http_remote_addr
            rate_limit 10r/s
            burst 5
            rate_limit_status 429
        }
    }
    abuse_protection {
        enabled true
        ban_time 600
        events {
            rate_limit {
                apply zone api_zone
            }
        }
        whitelist {
            ip 127.0.0.1
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

echo "4. Running aggressive legitimate traffic (60s) — should get banned..."
run_loadgen 60 100 "/"

echo "5. Checking if requests are being rate-limited..."
for i in $(seq 1 10); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:80/")
    echo "  Request $i: HTTP $code"
done

echo "6. Running traffic via forward proxy (simulated) — should bypass bans..."
# Simulate forward proxy by setting X-Forwarded-For to 127.0.0.1
for i in $(seq 1 10); do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "X-Forwarded-For: 127.0.0.1" "http://localhost:80/")
    echo "  Proxy request $i: HTTP $code"
done

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

echo "=== Forward Proxy Whitelist Bypass Scenario Complete ==="
echo "Expected findings:"
echo "  - Legitimate clients get 429s after rate limit triggers"
echo "  - Attacker using forward proxy bypasses bans (127.0.0.1 whitelisted)"
echo "  - Abuse protection ban list shows legitimate IPs but not attacker"
echo "  - Agent must notice the forward proxy is stripping real IPs"
