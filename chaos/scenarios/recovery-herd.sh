#!/usr/bin/env bash
# recovery-herd.sh — Scenario: Take backend down, circuit breaker opens, then bring it back
#
# Tests whether the circuit breaker + half-open probe mechanism handles
# the thundering herd on recovery. The "fix" (bringing backend back) is
# what visibly causes the next issue — classic misdiagnosis trap.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== Recovery Thundering Herd Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running steady traffic..."
run_loadgen 20 10 "/"

echo "3. Taking down backend-1 and backend-2 (simulating outage)..."
stop_backend backend-1
stop_backend backend-2
sleep 5

echo "4. Running traffic during outage (enough time for circuit breaker to open)..."
run_loadgen 60 15 "/"

echo "5. Bringing backends back (the "fix" that causes the herd)..."
start_backend backend-1
start_backend backend-2

echo "6. Waiting for backends to become healthy..."
for i in 1 2; do
    wait_for_healthy "backend-${i}" 15 2 || true
done

echo "7. Running traffic during recovery window..."
run_loadgen 30 30 "/"

echo "8. Waiting for stability..."
sleep 15
run_loadgen 20 10 "/"

echo "=== Recovery Thundering Herd Scenario Complete ==="
echo "Expected findings:"
echo "  - During outage: backend-3 handles all traffic, possible errors"
echo "  - Circuit breaker opens for backend-1/backend-2"
echo "  - On recovery: probe/half-open traffic slams both backends simultaneously"
echo "  - Backends may flap unhealthy briefly"
echo "  - The recovery event is the visible 'cause' — not the original outage"
