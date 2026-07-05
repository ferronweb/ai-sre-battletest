#!/usr/bin/env bash
# recompression-corruption.sh — Scenario: Pre-compressed files get re-compressed
#
# Serves pre-compressed .zst file without Cache-Control: immutable.
# Ferron3 re-compresses the already-compressed file, producing garbage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Re-compression Corruption Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with compression enabled..."
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
    compression {
        enabled true
        min_length 200
        types text/html text/css application/json
    }
    root /var/www/static
    static {
        index index.html
        compression true
        etag true
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

echo "4. Running traffic to pre-compressed .zst file (60s)..."
# This should produce corrupt output because Ferron3 re-compresses
run_loadgen 60 50 "/static/index.html"

echo "5. Running traffic to .gz file (30s)..."
run_loadgen 30 20 "/static/compressed/index.html.gz"

echo "6. Checking response content for corruption..."
echo "  Normal HTML response:"
curl -s "http://localhost:80/static/index.html" | head -5
echo ""
echo "  Pre-compressed .zst response (may be corrupt):"
curl -s -H "Accept-Encoding: zstd" "http://localhost:80/static/compressed/index.html.zst" | head -5 || echo "(binary data)"

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

echo "=== Re-compression Corruption Scenario Complete ==="
echo "Expected findings:"
echo "  - Pre-compressed .zst files get re-compressed, producing garbage"
echo "  - Response has Content-Encoding: zstd but body is corrupt"
echo "  - Agent must check compression chain and Cache-Control headers"
echo "  - Fix: add Cache-Control: immutable to pre-compressed files"
