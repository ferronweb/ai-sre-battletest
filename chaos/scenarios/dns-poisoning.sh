#!/usr/bin/env bash
# dns-poisoning.sh — Scenario: Partial DNS pool poisoning
#
# One IP in the resolved pool blackholes (SYN accepted, never responds)
# while the others are healthy. Tests whether per-IP circuit breaker state
# in STRICT_DNS-style pooling actually isolates the bad IP fast, or whether
# round-robin keeps re-hitting it.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== DNS Poisoning Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Running baseline traffic..."
run_loadgen 20 10 "/"

echo "3. Simulating blackhole on backend-1..."
# Drop all incoming TCP traffic to port 3000 inside backend-1.
# The proxy will see connection timeouts (no SYN-ACK), simulating a blackhole.
compose exec -T backend-1 \
    iptables -A INPUT -p tcp --dport 3000 -j DROP

echo "4. Running traffic during blackhole simulation (60s)..."
run_loadgen 60 20 "/"

echo "5. Restoring backend-1..."
compose exec -T backend-1 \
    iptables -D INPUT -p tcp --dport 3000 -j DROP || true
compose restart backend-1
wait_for_healthy backend-1 10 2 || true

echo "=== DNS Poisoning Scenario Complete ==="
echo "Expected findings:"
echo "  - Backend-1 connections timeout while backends 2-3 are healthy"
echo "  - If per-IP circuit breaker works: backend-1 is isolated quickly"
echo "  - If not: round-robin keeps hitting backend-1, causing intermittent timeouts"
echo "  - Trace IDs will show which requests hit the blackholed backend"
