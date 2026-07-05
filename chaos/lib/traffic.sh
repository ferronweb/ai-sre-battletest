#!/usr/bin/env bash
# traffic.sh — Shared traffic generation functions for chaos scenarios
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-docker}"
PROXY="${PROXY:-traefik}"
COMPOSE_BASE="-f ${COMPOSE_DIR}/docker-compose.yml"
COMPOSE_PROXY="-f ${COMPOSE_DIR}/docker-compose.${PROXY}.yml"
COMPOSE_ALL="${COMPOSE_BASE} ${COMPOSE_PROXY}"

run_loadgen() {
    local duration="${1:-30}"
    local rate="${2:-10}"
    local rpath="${3:-/}"
    local method="${4:-GET}"
    shift $(( 4 > $# ? $# : 4 ))

    local extra_env=""
    for pair in "$@"; do
        extra_env="${extra_env} -e ${pair}"
    done

    docker compose ${COMPOSE_ALL} run --rm \
        -e TARGET_URL="${TARGET_URL:-http://proxy:80}" \
        -e RATE="${rate}" \
        -e DURATION_SECS="${duration}" \
        -e METHOD="${method}" \
        -e REQUEST_PATH="${rpath}" \
        -e OUTPUT_JSON=true \
        ${extra_env} \
        loadgen
}

run_loadgen_background() {
    local duration="${1:-30}"
    local rate="${2:-10}"
    local rpath="${3:-/}"
    local method="${4:-GET}"
    shift $(( 4 > $# ? $# : 4 ))

    local extra_env=""
    for pair in "$@"; do
        extra_env="${extra_env} -e ${pair}"
    done

    docker compose ${COMPOSE_ALL} run --rm -d \
        -e TARGET_URL="${TARGET_URL:-http://proxy:80}" \
        -e RATE="${rate}" \
        -e DURATION_SECS="${duration}" \
        -e METHOD="${method}" \
        -e REQUEST_PATH="${rpath}" \
        -e OUTPUT_JSON=true \
        ${extra_env} \
        loadgen
}

curl_proxy() {
    local path="${1:-/}"
    shift $(( 1 > $# ? $# : 1 ))
    curl -s "http://localhost:80${path}" "$@"
}

check_proxy_healthy() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:80/health" 2>/dev/null || echo "000")
    [ "${code}" = "200" ]
}
