#!/usr/bin/env bash
# docker.sh — Shared Docker helper functions for chaos scenarios
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-docker}"
PROXY="${PROXY:-traefik}"
COMPOSE_BASE="-f ${COMPOSE_DIR}/docker-compose.yml"
COMPOSE_PROXY="-f ${COMPOSE_DIR}/docker-compose.${PROXY}.yml"
COMPOSE_ALL="${COMPOSE_BASE} ${COMPOSE_PROXY}"

compose() {
    docker compose ${COMPOSE_ALL} "$@"
}

compose_chaos() {
    docker compose ${COMPOSE_ALL} -f "${COMPOSE_DIR}/docker-compose.chaos.yml" "$@"
}

set_backend_env() {
    local backend="$1" key="$2" value="$3"
    docker compose ${COMPOSE_ALL} exec -T "${backend}" \
        sh -c "echo 'export ${key}=${value}' >> /etc/profile.d/chaos.sh && \
               echo '${value}' > /tmp/${key} && \
               kill -HUP 1 2>/dev/null || true"
    # Note: env var injection via docker compose override + restart
    echo "set ${key}=${value} on ${backend}"
}

restart_backend() {
    local backend="$1"
    docker compose ${COMPOSE_ALL} restart "${backend}"
}

stop_backend() {
    local backend="$1"
    docker compose ${COMPOSE_ALL} stop "${backend}"
}

start_backend() {
    local backend="$1"
    docker compose ${COMPOSE_ALL} start "${backend}"
}

proxy_exec() {
    docker compose ${COMPOSE_ALL} exec -T proxy "$@"
}

backend_exec() {
    local backend="$1"
    shift
    docker compose ${COMPOSE_ALL} exec -T "${backend}" "$@"
}

wait_for_healthy() {
    local service="$1"
    local retries="${2:-30}"
    local delay="${3:-2}"
    echo "Waiting for ${service} to be healthy..."
    for i in $(seq 1 "${retries}"); do
        if docker compose ${COMPOSE_ALL} ps "${service}" 2>/dev/null | grep -q "(healthy)"; then
            echo "${service} is healthy"
            return 0
        fi
        sleep "${delay}"
    done
    echo "Timeout waiting for ${service}"
    return 1
}
