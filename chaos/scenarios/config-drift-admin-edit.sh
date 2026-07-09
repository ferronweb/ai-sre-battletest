#!/usr/bin/env bash
# config-drift-admin-edit.sh — Scenario: Live config edited via admin API, not committed to version control
#
# Someone uses POST /reload after editing the HOCON file directly to fix an
# incident. The fix never makes it into version control. A subsequent deploy
# overwrites it, bug resurfaces.
#
# Tests whether ferron_admin_reload_active_generation/reload_successful plus
# config diffing gives a way to notice "running config doesn't match git"
# before the regression.
#
# Ferron3 only — tests admin API reload and config inspection.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== Config Drift Admin Edit Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (tests admin API reload)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Recording baseline config and reload state..."
CONFIG_BEFORE=$(curl -s http://localhost:8081/config 2>/dev/null || echo "{}")
RELOAD_BEFORE=$(curl -s http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Config before: $(echo "${CONFIG_BEFORE}" | wc -c) bytes"
echo "   Reload state before: ${RELOAD_BEFORE}"

echo "3. Running baseline traffic (20s)..."
run_loadgen 20 10 "/"

echo "4. Editing config file DIRECTLY (bypassing version control)..."
# Add a custom header to simulate an emergency fix
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
        request_header +X-Emergency-Fix "applied-via-admin-edit"
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
    }
}
FERRONEOF

echo "5. Triggering reload via admin API..."
RELOAD_RESULT=$(curl -s -X POST http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Reload result: ${RELOAD_RESULT}"
sleep 3

echo "6. Verifying fix is active..."
HEADERS=$(curl -s -D - http://localhost:80/ 2>/dev/null | head -20 || echo "failed")
echo "   Response headers: $(echo "${HEADERS}" | grep -i 'x-emergency' || echo '(not found)')"

echo "7. Recording reload state after edit..."
RELOAD_AFTER=$(curl -s http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Reload state after: ${RELOAD_AFTER}"

echo "8. Running traffic with emergency fix active (20s)..."
run_loadgen 20 10 "/"

echo "9. Simulating 'clean deploy' that overwrites the fix..."
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

echo "10. Reloading with 'clean' config..."
curl -s -X POST http://localhost:8081/reload 2>/dev/null || true
sleep 3

echo "11. Verifying fix is gone..."
HEADERS_AFTER=$(curl -s -D - http://localhost:80/ 2>/dev/null | head -20 || echo "failed")
echo "   Response headers after deploy: $(echo "${HEADERS_AFTER}" | grep -i 'x-emergency' || echo '(not found - fix reverted)')"

echo "12. Checking final config and reload state..."
CONFIG_AFTER=$(curl -s http://localhost:8081/config 2>/dev/null || echo "{}")
RELOAD_FINAL=$(curl -s http://localhost:8081/reload 2>/dev/null || echo "{}")
echo "   Config after: $(echo "${CONFIG_AFTER}" | wc -c) bytes"
echo "   Reload state: ${RELOAD_FINAL}"

echo "13. Running traffic after regression (20s)..."
run_loadgen 20 10 "/"

echo "=== Config Drift Admin Edit Scenario Complete ==="
echo "Expected findings:"
echo "  - Emergency fix applied via direct file edit + POST /reload"
echo "  - X-Emergency-Fix header visible in responses after reload"
echo "  - 'Clean deploy' overwrites fix, header disappears"
echo "  - ferron_admin.reload.active_generation increments with each reload"
echo "  - Agent must compare running config (GET /config) with on-disk config"
echo "  - Drift is detectable: running config has header, git version doesn't"
echo "  - Scenario tests whether agent notices config/version mismatch"
