#!/usr/bin/env bash
# directory-traversal.sh — Scenario: Crafted URLs escape web root
#
# Configures Ferron3 static file serving without URL sanitization.
# Attacker uses ../ sequences to access files outside web root.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Directory Traversal Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "3. Configuring Ferron3 with static file serving (url_sanitize disabled)..."
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
        browse false
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

echo "4. Running normal static file traffic (30s)..."
run_loadgen 30 20 "/static/index.html"

echo "5. Running traversal attack traffic (60s)..."
# Mix of normal and traversal requests
for i in $(seq 1 60); do
    if [ $((i % 5)) -eq 0 ]; then
        # Traversal attempt every 5th request
        curl -s -o /dev/null -w "%{http_code} " "http://localhost:80/static/../../etc/passwd" &
    else
        # Normal request
        curl -s -o /dev/null -w "%{http_code} " "http://localhost:80/static/index.html" &
    fi
    if [ $((i % 10)) -eq 0 ]; then
        wait
        sleep 1
    fi
done
wait
echo ""

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

echo "=== Directory Traversal Scenario Complete ==="
echo "Expected findings:"
echo "  - Normal requests return 200 with HTML"
echo "  - Traversal requests may return file contents (if url_sanitize disabled)"
echo "  - Agent must notice the path traversal in access logs"
echo "  - Security vulnerability disguised as a routing issue"
