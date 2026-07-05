#!/usr/bin/env bash
# admin-api-exposed.sh — Scenario: Admin API without auth, attacker reloads config
#
# Exposes Ferron3 admin API on 0.0.0.0:8081 without allowed_ip restriction.
# Attacker calls /admin/api/v1/reload, flushing cache and causing outage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Admin API Exposed Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Configuring Ferron3 with cache and exposed admin API..."
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
    cache {
        enabled true
        default_max_age 300
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

echo "3. Running baseline traffic to populate cache (30s)..."
run_loadgen 30 50 "/"

echo "4. Running traffic during attack (60s)..."
run_loadgen_background 60 100 "/"

echo "5. Attacker calls admin API reload (flushes cache)..."
for i in 1 2 3; do
    echo "  Reloading config (attempt $i)..."
    curl -s -X POST "http://localhost:8081/reload" || true
    sleep 5
done

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

echo "=== Admin API Exposed Scenario Complete ==="
echo "Expected findings:"
echo "  - Admin API accessible without authentication on port 8081"
echo "  - Cache flush after each reload causes latency spike"
echo "  - Agent must notice admin API access in logs"
echo "  - Agent must correlate reload events with cache misses"
