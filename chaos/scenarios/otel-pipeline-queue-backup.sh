#!/usr/bin/env bash
# otel-pipeline-queue-backup.sh — Scenario: OTel collector goes down, Ferron's observability event queue backs up
#
# Stops the OTel collector while running high traffic. Ferron's internal
# event queue (ferron_admin_observability_event_queue_len) should back up.
# Tests whether Ferron drops events cleanly and stays healthy, buffers to
# disk and fills it, or blocks request handling waiting on a full queue.
#
# This is the meta-failure of "observability breaks during the incident
# you need observability for."
#
# Ferron3 only — tests admin API /status metrics.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-ferron3}"
echo "=== OTel Pipeline Queue Backup Scenario (PROXY=${PROXY}) ==="

if [ "${PROXY}" != "ferron3" ]; then
    echo "SKIP: This scenario is Ferron3-only (requires admin API /status)"
    exit 0
fi

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Verifying OTel collector is healthy..."
wait_for_healthy otel-collector 10 2 || true

echo "3. Running baseline traffic (30s)..."
run_loadgen 30 20 "/"

echo "4. Checking baseline admin API status..."
STATUS_BASELINE=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
echo "   Baseline status: ${STATUS_BASELINE}"

echo "5. Stopping OTel collector (simulating pipeline failure)..."
compose stop otel-collector
sleep 2

echo "6. Running high traffic while OTel is down (60s)..."
run_loadgen_background 60 50 "/"

echo "7. Polling admin API /status every 10s for 60s..."
for i in 1 2 3 4 5 6; do
    sleep 10
    STATUS=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
    DROPPED=$(echo "${STATUS}" | grep -o '"observability_events_dropped":[0-9]*' | cut -d: -f2 || echo "0")
    QUEUE_LEN=$(echo "${STATUS}" | grep -o '"observability_event_queue_len":[0-9]*' | cut -d: -f2 || echo "0")
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health 2>/dev/null || echo "000")
    echo "   t+${i}0s: dropped=${DROPPED} queue_len=${QUEUE_LEN} health=${HEALTH}"
done

echo "8. Waiting for traffic containers to finish..."
sleep 10

echo "9. Starting OTel collector back up..."
compose start otel-collector
sleep 10

echo "10. Checking recovery status..."
STATUS_RECOVERY=$(curl -s http://localhost:8081/status 2>/dev/null || echo "{}")
DROPPED_RECOVERY=$(echo "${STATUS_RECOVERY}" | grep -o '"observability_events_dropped":[0-9]*' | cut -d: -f2 || echo "0")
QUEUE_RECOVERY=$(echo "${STATUS_RECOVERY}" | grep -o '"observability_event_queue_len":[0-9]*' | cut -d: -f2 || echo "0")
echo "   Recovery: dropped=${DROPPED_RECOVERY} queue_len=${QUEUE_RECOVERY}"

echo "11. Running post-recovery traffic (20s)..."
run_loadgen 20 10 "/"

echo "=== OTel Pipeline Queue Backup Scenario Complete ==="
echo "Expected findings:"
echo "  - OTel collector stops receiving data while down"
echo "  - observability_events_dropped should increment"
echo "  - observability_event_queue_len may spike"
echo "  - Ferron should stay healthy (HTTP 200 on /health) throughout"
echo "  - After collector restarts, queue should drain"
echo "  - Agent must distinguish 'observability pipeline broken' from 'app is down'"
