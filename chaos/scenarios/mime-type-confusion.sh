#!/usr/bin/env bash
# mime-type-confusion.sh — Scenario: Custom extension gets wrong MIME type
#
# Serves .tmpl files that should be text/html but get application/octet-stream.
# Browser downloads files instead of rendering.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== MIME Type Confusion Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with static file serving..."
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

echo "4. Running traffic to .html files — correct MIME type (30s)..."
run_loadgen 30 20 "/static/index.html"

echo "5. Running traffic to .tmpl files — wrong MIME type (60s)..."
run_loadgen 60 50 "/static/page.tmpl"

echo "6. Running traffic to .xml files — check MIME type (30s)..."
run_loadgen 30 20 "/static/feed.xml"

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

echo "=== MIME Type Confusion Scenario Complete ==="
echo "Expected findings:"
echo "  - .html files have Content-Type: text/html"
echo "  - .tmpl files have Content-Type: application/octet-stream (wrong)"
echo "  - Browser tries to download .tmpl files instead of rendering"
echo "  - Agent must notice the wrong MIME type in response headers"
