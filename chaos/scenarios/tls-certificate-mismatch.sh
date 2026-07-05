#!/usr/bin/env bash
# tls-certificate-mismatch.sh — TLS certificate expires during the test window
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/docker.sh"
source "${SCRIPT_DIR}/../lib/traffic.sh"

PROXY="${1:-traefik}"
echo "=== TLS Certificate Mismatch Scenario (PROXY=${PROXY}) ==="

echo "1. Ensuring stack is up..."
compose up -d
for i in 1 2 3; do
    wait_for_healthy "backend-${i}" 10 2 || true
done

echo "2. Generating short-lived TLS certificate (expires in 10s)..."
mkdir -p /tmp/tls-certs
openssl req -x509 -newkey rsa:2048 -keyout /tmp/tls-certs/key.pem -out /tmp/tls-certs/cert.pem \
  -not_before $(date -u +%Y%m%d%H%M%SZ) -not_after $(date -u -d "+10 seconds" +%Y%m%d%H%M%SZ) \
  -nodes -subj '/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1' \
  -set_serial 1 2>/dev/null

echo "3. Writing TLS config for proxy and adding port 443..."
if [ "${PROXY}" = "traefik" ]; then
    # Copy certs into Traefik container
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "mkdir -p /tmp/tls-certs"
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /tmp/tls-certs/cert.pem" < /tmp/tls-certs/cert.pem
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /tmp/tls-certs/key.pem" < /tmp/tls-certs/key.pem

    # Write TLS dynamic config
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /etc/traefik/dynamic/tls.yml" << 'EOF'
tls:
  certificates:
    - certFile: /tmp/tls-certs/cert.pem
      keyFile: /tmp/tls-certs/key.pem
  options:
    default:
      sniStrict: true
EOF

    # Add HTTPS entrypoint via compose override and restart
    cat > /tmp/traefik-tls-override.yml << EOF
services:
  proxy:
    ports:
      - "443:443"
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--providers.docker.network=web"
      - "--providers.file.directory=/etc/traefik/dynamic"
      - "--providers.file.watch=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.observability.traceVerbosity=detailed"
      - "--experimental.otlpLogs=true"
      - "--accesslog.otlp.grpc=true"
      - "--accesslog.otlp.grpc.endpoint=otel-collector:4317"
      - "--accesslog.otlp.grpc.insecure=true"
      - "--log.otlp.grpc=true"
      - "--log.otlp.grpc.endpoint=otel-collector:4317"
      - "--log.otlp.grpc.insecure=true"
      - "--metrics.otlp.grpc=true"
      - "--metrics.otlp.grpc.endpoint=otel-collector:4317"
      - "--metrics.otlp.grpc.insecure=true"
      - "--tracing.otlp.grpc=true"
      - "--tracing.otlp.grpc.endpoint=otel-collector:4317"
      - "--tracing.otlp.grpc.insecure=true"
      - "--tracing.serviceName=traefik"
      - "--tracing.sampleRate=1.0"
EOF
    docker compose ${COMPOSE_ALL} -f /tmp/traefik-tls-override.yml up -d proxy
    wait_for_healthy proxy 10 2 || true
else
    # Copy certs into Ferron 3 container
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "mkdir -p /tmp/tls-certs"
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /tmp/tls-certs/cert.pem" < /tmp/tls-certs/cert.pem
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "cat > /tmp/tls-certs/key.pem" < /tmp/tls-certs/key.pem

    cat > /tmp/ferron3-tls.conf << FERRONEOF
{
    admin { listen "0.0.0.0:8081" }
    observability {
        provider otlp
        logs http://otel-collector:4317/v1/logs
        metrics http://otel-collector:4317/v1/metrics
        traces http://otel-collector:4317/v1/traces
    }
}
:443 {
    tls {
        provider manual
        cert "/tmp/tls-certs/cert.pem"
        key "/tmp/tls-certs/key.pem"
    }
    proxy {
        upstream http://backend-1:3000
        upstream http://backend-2:3000
        upstream http://backend-3:3000
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
    cp /tmp/ferron3-tls.conf docker/config/ferron3/ferron.conf
    cat > /tmp/ferron3-tls-port.yml << EOF
services:
  proxy:
    ports:
      - "80:80"
      - "443:443"
EOF
    docker compose ${COMPOSE_ALL} -f /tmp/ferron3-tls-port.yml up -d --force-recreate proxy
    wait_for_healthy proxy 10 2 || true
fi

echo "4. Running traffic against HTTP (port 80) — should be fine (30s)..."
run_loadgen 30 10 "/"

echo "5. Waiting for cert to expire... (15s)..."
sleep 15

echo "6. Running traffic against HTTPS (port 443) — intermittent failures expected (60s)..."
TARGET_URL="https://localhost:443" run_loadgen 60 10 "/" "GET" "CONCURRENCY=50" "TIMEOUT_SECS=10" "HEADERS=X-Chaos:tls-certificate-mismatch"

echo "7. Restoring proxy config..."
if [ "${PROXY}" = "traefik" ]; then
    docker compose ${COMPOSE_ALL} exec -T proxy sh -c "rm -f /etc/traefik/dynamic/tls.yml /tmp/tls-certs/*"
    docker compose ${COMPOSE_ALL} up -d --force-recreate proxy
    wait_for_healthy proxy 10 2 || true
    rm -f /tmp/traefik-tls-override.yml
else
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
    rm -f /tmp/ferron3-tls.conf /tmp/ferron3-tls-port.yml
fi

echo "8. Cleaning up certs..."
rm -rf /tmp/tls-certs

echo "=== TLS Certificate Mismatch Scenario Complete ==="
echo "Expected: HTTP works, HTTPS has intermittent TLS handshake failures"
