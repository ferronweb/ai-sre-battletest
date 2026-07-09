PROXY ?= traefik
COMPOSE_DIR := docker
COMPOSE_BASE := -f $(COMPOSE_DIR)/docker-compose.yml
COMPOSE_PROXY := -f $(COMPOSE_DIR)/docker-compose.$(PROXY).yml
COMPOSE_ALL := $(COMPOSE_BASE) $(COMPOSE_PROXY)
COMPOSE_CHAOS := -f $(COMPOSE_DIR)/docker-compose.chaos.yml
COMPOSE_LIGHTWEIGHT := -f $(COMPOSE_DIR)/docker-compose.ferron3-lightweight.yml
COMPOSE_LOGS_ONLY := -f $(COMPOSE_DIR)/docker-compose.ferron3-logs-only.yml

.PHONY: up down build rebuild restart logs ps \
        up-chaos down-chaos \
        up-lightweight down-lightweight up-logs-only down-logs-only \
        scenario-gray-failure scenario-latency \
        scenario-recovery-herd scenario-dns-poisoning \
        scenario-timeout-mismatch \
        scenario-retry-amplification scenario-circuit-breaker \
        scenario-health-check scenario-observability-backpressure \
        scenario-tls-certificate \
        scenario-cache-stampede scenario-cache-poisoning \
        scenario-cache-key-fragmentation scenario-forward-proxy-whitelist-bypass \
        scenario-directory-traversal scenario-mime-type-confusion \
        scenario-rate-limit-burst scenario-recompression-corruption \
        scenario-compression-exclusion scenario-session-ticket-restart \
        scenario-mtls-ca-missing scenario-forwarded-auth-down \
        scenario-basic-auth-concurrency scenario-trace-flood-disk \
        scenario-admin-api-exposed \
        scenario-otel-pipeline-queue-backup scenario-pool-exhaustion-slow-route \
        scenario-retry-idempotency-hazard scenario-dns-record-change \
        scenario-cascading-downstream-trace scenario-config-drift-admin-edit \
        scenario-missing-dependency-reload

# ─── Lifecycle ───────────────────────────────────────────────

up:
	docker compose $(COMPOSE_ALL) up -d

down:
	docker compose $(COMPOSE_ALL) down -v

build:
	docker build -t battletest-backend backend/
	docker build -t battletest-loadgen loadgen/

build-chaos-agents:
	-docker build -t dns-poison-agent chaos/agents/dns-poison/
	-docker build -t trace-mangler-agent chaos/agents/trace-mangler/
	-docker build -t trace-flood-agent chaos/agents/trace-flood/
	-docker build -t battletest-auth-backend chaos/agents/auth-backend/

rebuild: build down up

restart: down up

logs:
	docker compose $(COMPOSE_ALL) logs -f

ps:
	docker compose $(COMPOSE_ALL) ps

up-chaos:
	@echo "Building chaos agents..."
	-docker build -t dns-poison-agent chaos/agents/dns-poison/
	-docker build -t trace-mangler-agent chaos/agents/trace-mangler/
	-docker build -t trace-flood-agent chaos/agents/trace-flood/
	-docker build -t battletest-auth-backend chaos/agents/auth-backend/
	docker compose $(COMPOSE_ALL) $(COMPOSE_CHAOS) up -d

down-chaos:
	docker compose $(COMPOSE_ALL) $(COMPOSE_CHAOS) down

# ─── Lightweight Profiles (Ferron 3) ─────────────────────────

up-lightweight:
	@echo "Starting lightweight stack (logs + Prometheus)..."
	docker compose $(COMPOSE_LIGHTWEIGHT) up -d

down-lightweight:
	docker compose $(COMPOSE_LIGHTWEIGHT) down -v

up-logs-only:
	@echo "Starting logs-only stack..."
	docker compose $(COMPOSE_LOGS_ONLY) up -d

down-logs-only:
	docker compose $(COMPOSE_LOGS_ONLY) down -v

logs-lightweight:
	docker compose $(COMPOSE_LIGHTWEIGHT) logs -f

logs-logs-only:
	docker compose $(COMPOSE_LOGS_ONLY) logs -f

ps-lightweight:
	docker compose $(COMPOSE_LIGHTWEIGHT) ps

ps-logs-only:
	docker compose $(COMPOSE_LOGS_ONLY) ps

# ─── Scenarios ───────────────────────────────────────────────

scenario-gray-failure:
	@echo "Running Gray Failure scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/gray-failure.sh $(PROXY)

scenario-latency:
	@echo "Running Latency Injection scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/latency-injection.sh $(PROXY)

scenario-recovery-herd:
	@echo "Running Recovery Thundering Herd scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/recovery-herd.sh $(PROXY)

scenario-dns-poisoning:
	@echo "Running DNS Poisoning scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/dns-poisoning.sh $(PROXY)

scenario-timeout-mismatch:
	@echo "Running Timeout Mismatch scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/timeout-mismatch.sh $(PROXY)

# ─── New Scenarios ────────────────────────────────────────────

scenario-retry-amplification:
	@echo "Running Retry Amplification scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/retry-amplification.sh $(PROXY)

scenario-circuit-breaker:
	@echo "Running Circuit Breaker Blind Spot scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/circuit-breaker-blind-spot.sh $(PROXY)

scenario-health-check:
	@echo "Running Health Check Manipulation scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/health-check-manipulation.sh $(PROXY)

scenario-observability-backpressure:
	@echo "Running Observability Backpressure scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/observability-backpressure.sh $(PROXY)

scenario-tls-certificate:
	@echo "Running TLS Certificate expiry scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/tls-certificate-mismatch.sh $(PROXY)

# ─── Ferron3 Cache/Rate Limit/Security Scenarios ─────────────

scenario-cache-stampede:
	@echo "Running Cache Stampede scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/cache-stampede.sh $(PROXY)

scenario-cache-poisoning:
	@echo "Running Cache Poisoning scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/cache-poisoning.sh $(PROXY)

scenario-cache-key-fragmentation:
	@echo "Running Cache Key Fragmentation scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/cache-key-fragmentation.sh $(PROXY)

scenario-forward-proxy-whitelist-bypass:
	@echo "Running Forward Proxy Whitelist Bypass scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/forward-proxy-whitelist-bypass.sh $(PROXY)

scenario-directory-traversal:
	@echo "Running Directory Traversal scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/directory-traversal.sh $(PROXY)

scenario-mime-type-confusion:
	@echo "Running MIME Type Confusion scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/mime-type-confusion.sh $(PROXY)

scenario-rate-limit-burst:
	@echo "Running Rate Limit Burst Mismatch scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/rate-limit-burst.sh $(PROXY)

scenario-recompression-corruption:
	@echo "Running Re-compression Corruption scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/recompression-corruption.sh $(PROXY)

scenario-compression-exclusion:
	@echo "Running Compression Type Exclusion scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/compression-exclusion.sh $(PROXY)

scenario-session-ticket-restart:
	@echo "Running Session Ticket Key Loss on Restart scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/session-ticket-restart.sh $(PROXY)

scenario-mtls-ca-missing:
	@echo "Running mTLS CA File Missing scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/mtls-ca-missing.sh $(PROXY)

scenario-forwarded-auth-down:
	@echo "Running Forwarded Auth Backend Down scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/forwarded-auth-down.sh $(PROXY)

scenario-basic-auth-concurrency:
	@echo "Running Basic Auth Concurrency Lockout scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/basic-auth-concurrency.sh $(PROXY)

scenario-trace-flood-disk:
	@echo "Running Trace Flood Fills Disk scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/trace-flood-disk.sh $(PROXY)

scenario-admin-api-exposed:
	@echo "Running Admin API Without Auth scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/admin-api-exposed.sh $(PROXY)

# ─── Debugging Story Scenarios ──────────────────────────────

scenario-otel-pipeline-queue-backup:
	@echo "Running OTel Pipeline Queue Backup scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/otel-pipeline-queue-backup.sh $(PROXY)

scenario-pool-exhaustion-slow-route:
	@echo "Running Pool Exhaustion Slow Route scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/pool-exhaustion-slow-route.sh $(PROXY)

scenario-retry-idempotency-hazard:
	@echo "Running Retry Idempotency Hazard scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/retry-idempotency-hazard.sh $(PROXY)

scenario-dns-record-change:
	@echo "Running DNS Record Change scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/dns-record-change.sh $(PROXY)

scenario-cascading-downstream-trace:
	@echo "Running Cascading Downstream Trace scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/cascading-downstream-trace.sh $(PROXY)

scenario-config-drift-admin-edit:
	@echo "Running Config Drift Admin Edit scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/config-drift-admin-edit.sh $(PROXY)

scenario-missing-dependency-reload:
	@echo "Running Missing Dependency Reload scenario (PROXY=$(PROXY))..."
	PROXY=$(PROXY) COMPOSE_DIR=$(COMPOSE_DIR) \
		./chaos/scenarios/missing-dependency-reload.sh $(PROXY)

# ─── Utility ────────────────────────────────────────────────

prompt-traefik:
	@echo "=== Traefik System Prompt ==="
	@cat prompts/traefik/system-prompt.md
	@echo ""
	@echo "=== Scenario Prompt ==="
	@echo "Pick a scenario:"
	@ls prompts/traefik/scenarios/

prompt-ferron3:
	@echo "=== Ferron 3 System Prompt ==="
	@cat prompts/ferron3/system-prompt.md
	@echo ""
	@echo "=== Scenario Prompt ==="
	@echo "Pick a scenario:"
	@ls prompts/ferron3/scenarios/

prompt-ferron3-lightweight:
	@echo "=== Ferron 3 Lightweight System Prompt ==="
	@cat prompts/ferron3/system-prompt-lightweight.md
	@echo ""
	@echo "=== Scenario Prompt ==="
	@echo "Pick a scenario:"
	@ls prompts/ferron3/scenarios/
