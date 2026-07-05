#!/usr/bin/env bash
# trace-flood-disk.sh — Scenario: Trace flood fills disk via high sample rate
#
# Enables trace_sample_rate 1.0 and runs high traffic + trace-flood agent.
# Trace logs fill disk, potentially crashing Ferron3. Tests whether the
# agent distinguishes "app is down" from "disk is full from traces".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Trace Flood Disk Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with trace_sample_rate 1.0..."
cat > docker/config/ferron3/ferron.conf << 'FERRONEOF'
{
    admin { listen "0.0.0.0:8081" }
    observability {
        provider otlp
        logs http://otel-collector:4317/v1/logs
        metrics http://otel-collector:4317/v1/metrics
        traces http://otel-collector:4317/v1/traces
    }
    trace_sample_rate 1.0
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

echo "4. Running high traffic (60s)..."
run_loadgen_background 60 100 "/"

echo "5. Launching trace-flood agent (90s, 50k spans/s)..."
compose_chaos up -d trace-flood
sleep 90
compose_chaos stop trace-flood

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

echo "=== Trace Flood Disk Scenario Complete ==="
echo "Expected findings:"
echo "  - trace_sample_rate=1.0 causes massive trace log volume"
echo "  - trace-flood agent adds 50k high-cardinality spans/sec"
echo "  - Disk usage spikes, may cause OOM or crash"
echo "  - Application /health may remain 200 even as observability pipeline degrades"
echo "  - Agent must distinguish app failure from telemetry/disk failure"
