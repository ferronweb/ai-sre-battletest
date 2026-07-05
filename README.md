# AI SRE Battle-Test Harness

A generalized chaos engineering harness for evaluating AI SRE agents against
realistic, deceptive failure modes. Supports pluggable reverse proxies
(Traefik, Ferron 3, etc.) with a shared observability stack.

---

## Quick Start

### Prerequisites

- Docker + Docker Compose (v2)
- Rust toolchain (for building backend/loadgen from source)
- An AI agent with MCP tooling (e.g., OpenCode with Grafana MCP)

### One-Command Start

```bash
make up
```

That's it. After `make up`, the following endpoints are live:

| Endpoint | URL | Purpose |
|----------|-----|---------|
| Application | http://localhost:80 | Service under test |
| Grafana | http://localhost:3000 | Pre-provisioned with Tempo, Mimir, Loki datasources |
| Tempo API | http://localhost:3200 | Direct trace querying |
| Mimir API | http://localhost:9009 | Direct metrics querying |
| Loki API | http://localhost:3100 | Direct log querying |
| Traefik dashboard | http://localhost:8080 | Proxy dashboard (Traefik only) |
| Ferron 3 Admin API | http://localhost:8081 | Ferron 3 only |

### Build (optional)

If you need to rebuild the backend or loadgen images:

```bash
make build   # builds backend/ and loadgen/ Docker images
```

### Run a Battle-Test Session

See the [Battle-Test Workflow](#battle-test-workflow) section for the full
step-by-step process. In brief:

```bash
# 1. Run the scenario (injects the failure)
make scenario-gray-failure

# 2. Start your AI agent with Grafana MCP
# 3. Paste the combined prompt (system + scenario)
# 4. Let the agent investigate
# 5. Review the transcript
# 6. Shut down
make down
```

### Stop

```bash
make down   # tears down all containers and volumes
```

---

## Architecture

```
┌─ User / LoadGen ─────────────────────────────────┐
│  http://localhost:80                               │
└──────────────────────┬───────────────────────────┘
                       │
              ┌────────▼────────┐
              │    Proxy        │  ← Traefik or Ferron 3
              │  (port 80)      │
              └────────┬────────┘
                       │ OTLP logs/metrics/traces
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
   backend-1      backend-2      backend-3
   (:3000)        (:3000)        (:3000)
         │             │             │
         └─────────────┼─────────────┘
                       │
              ┌────────▼────────┐
              │  OpenTelemetry  │
              │   Collector     │
              └───┬─────┬──────┘
                  │     │
          ┌───────▼┐ ┌──▼────────┐
          │ Tempo  │ │  Mimir    │
          │ traces │ │  metrics  │
          └────────┘ └───────────┘
          ┌────────┐ ┌───────────┐
          │  Loki  │ │  Grafana  │
          │  logs  │ │  :3000    │
          └────────┘ └───────────┘
```

### Components

| Component | Role | Port(s) |
|-----------|------|---------|
| `proxy` (Traefik/Ferron 3) | Reverse proxy, load balancer | 80, 8080 (Traefik dash) |
| `backend-1..3` | Rust/Axum test backends | 3000 (internal) |
| `otel-collector` | OTLP receiver + router | 4317 (gRPC), 4318 (HTTP) |
| `tempo` | Distributed tracing store | 3200 |
| `mimir` | Metrics store (Prometheus-compatible) | 9009 |
| `loki` | Log store | 3100 |
| `grafana` | Visualization (pre-provisioned datasources) | 3000 |

### Networks

- **`web`**: proxy + backends (application traffic)
- **`observability`**: proxy + otel-collector + tempo + mimir + loki + grafana

The proxy bridges both networks.

---

## Battle-Test Workflow

This is the end-to-end process for running a battle-test against an AI SRE
agent. Each scenario tests a different failure mode — the agent must diagnose
the issue using only the observability data, without being told the root cause.

### Step 1: Start the Stack

```bash
# Choose your proxy (default is Traefik)
make up                          # Traefik
PROXY=ferron3 make up            # Ferron 3
```

Verify the stack is healthy:
```bash
curl http://localhost:80/health   # should return 200
```

### Step 2: Run the Scenario

Run a scenario script to inject the failure condition:

```bash
# Choose a scenario:
make scenario-gray-failure          # 100% error on /error route of one backend
make scenario-latency               # 3s delay on two backends, no errors
make scenario-circuit-breaker       # 5s latency, zero errors (cb blind spot)
make scenario-retry-amplification   # Proxy retries amplify intermittent errors
make scenario-health-check          # Health check path mismatch
make scenario-observability-backpressure   # Trace flood overwhelms OTel
make scenario-tls-certificate       # Expired TLS cert
# ... and more — see [Scenario Descriptions](#scenario-descriptions)
```

The scenario script will:
1. Start the stack if not already running
2. Inject the failure condition (env vars, iptables, docker stop, etc.)
3. Run traffic through the system
4. Clean up (remove injected chaos)

### Step 3: Prepare the Prompt

Get the combined prompt to paste into your AI agent:

```bash
# For Traefik:
make prompt-traefik

# For Ferron 3:
make prompt-ferron3
```

This prints the system prompt + available scenario prompts. Concatenate the
**system prompt** with the **scenario-specific incident brief** and paste it
into your agent. The scenario brief describes symptoms without revealing the
root cause.

### Step 4: Start Your AI Agent

Launch your AI agent with Grafana MCP (or your preferred MCP tooling). The
agent should have access to:

- **Grafana** at `http://localhost:3000` — pre-provisioned with Tempo, Mimir,
  and Loki datasources for querying traces, metrics, and logs
- **Application** at `http://localhost:80` — the service under test
- **Tempo API** at `http://localhost:3200` — direct trace querying
- **Mimir API** at `http://localhost:9009` — direct metrics querying
- **Loki API** at `http://localhost:3100` — direct log querying

> **Security note**: When using OpenCode, place an `opencode.json` in your
> working directory to prevent the AI from reading files outside the project:
> ```json
> {
>   "$schema": "https://opencode.ai/config.json",
>   "permission": {
>     "external_directory": "deny"
>   }
> }
> ```
> The AI agent should run from a **separate directory** from the harness
> directory — this prevents the agent from accidentally reading harness files
> (like scenario scripts or the prompt files) that it shouldn't see.

### Step 5: Let the Agent Investigate

The agent should:
- Identify anomalies from the provided symptoms
- Query Grafana Explore for traces, metrics, and logs
- Correlate evidence across layers (proxy + backend + observability)
- Cite specific trace IDs, log lines, and metric queries

### Step 6: Review the Transcript

After the agent completes its investigation, review the transcript against the
evaluation criteria:

1. **Root cause accuracy** — Did they identify the correct failure mechanism?
2. **Specificity** — Do they cite specific trace IDs, log lines, and metric
   queries (not a plausible narrative)?
3. **Layer isolation** — Did they check both proxy and backend layers?
4. **Dual-cause detection** — For stacked scenarios, did they find both
   independent issues?

### Step 7: Clean Up

Before running the next scenario, shut down the stack:

```bash
make down   # tears down all containers and volumes
```

Then repeat from Step 1 with a different proxy or scenario.

---

## Scenario Descriptions

Each scenario injects a specific failure mode and tests whether the AI agent
can identify the root cause from observability data alone. The scenario brief
(described below) presents symptoms without revealing the root cause.

### 1. Gray Failure

Injects 100% error rate on the `/error` route of one backend while `/health`
stays green. The aggregate error rate barely moves. Tests whether the agent
finds the specific failing route instead of stopping at the top-level dashboard.

**Mechanism**: Backend env var `ERROR_PCT=1.0` on one of three replicas.
**Signal**: Only `/error` returns 500s; `/health` is always 200.

### 2. Latency Injection

Adds 3s delay to two of three backends. Circuit breaker (keyed on error rate)
doesn't trip. p50 stays fine, p99 explodes, queues build silently.

**Mechanism**: Backend env var `LATENCY_MS=3000` on the affected replicas.
**Signal**: p50 normal, p99 ~3s, no 5xx errors.

### 3. Recovery Thundering Herd

Takes two backends down long enough for the circuit breaker to open, then
brings them back. Probes/half-open traffic slams both simultaneously, causing
potential flapping.

**Mechanism**: `docker stop` / `docker start` on backends.
**Signal**: Brief outage, then recovery spike, then potential re-failure.

### 4. DNS Poisoning

Simulates one backend IP blackholing (SYN accepted, no response). Tests whether
per-IP circuit breaker isolation works or round-robin keeps re-hitting the bad
IP.

**Mechanism**: iptables DROP rule on one backend + traffic.
**Signal**: Intermittent timeouts on requests that hit the blackholed backend.

### 5. Timeout Mismatch

Misconfigures timeouts so client timeout < proxy timeout < backend response
time. Client retries while proxy is still waiting on the abandoned backend
call, doubling load with no visible cause in any single layer's logs.

**Mechanism**: Backend delay + proxy timeout reconfiguration.
**Signal**: Client timeouts, retries, doubled request rate at proxy, abandoned
backend connections.

### 6. Retry Amplification Storm

Proxy is configured to retry on failure. Backend intermittently returns 503.
Each original request generates 3-4 retries, amplifying the failure into a
request storm that overwhelms the remaining healthy backends.

**Mechanism**: Proxy-level retry config (4 attempts on Traefik, `retry_connection`
on Ferron 3) + `ERROR_PCT=0.3` and `ERROR_CODE=503` on two of three backends.
**Signal**: Proxy request rate is 2-4x client send rate; Backend-3 handles
overflow from retries despite being healthy.

### 7. Circuit Breaker Blind Spot

Extreme latency (5s) on two backends with zero errors. Circuit breaker watches
error count/ratio and stays closed. Load balancer uses `round_robin` (does not
adapt to latency). p99 is unusable while p50 stays fine.

**Mechanism**: `LATENCY_MS=5000` on backend-1 and backend-2 with
`ERROR_PCT=0.0`. Proxy uses `round_robin` + error-count circuit breaker.
**Signal**: p99 ~5s, p50 normal, 0% errors. Circuit breaker never opens.

### 8. Health Check Manipulation

Proxy health check probes `/` (always returns 200) instead of `/health`.
Backend's `/health` returns 503, but the backend stays in rotation because
the health check path is wrong. Long-lived `/stream` connections are
interrupted by 40% error rate.

**Mechanism**: `HEALTHY=false` (makes `/health` return 503) + `ERROR_PCT=0.4`.
Proxy health check configured with `path: /` instead of `/health`.
**Signal**: Proxy marks backend healthy; backend's `/health` returns 503;
~40% of requests to the affected backend fail mid-stream.

### 9. Observability Pipeline Backpressure

High-cardinality trace flood overwhelms the OTel Collector. Grafana shows
data gaps. Application `/health` remains 200 throughout. Agent must
distinguish "app is down" from "telemetry is down."

**Mechanism**: `trace-flood` agent sends 50,000 spans/sec with 20
high-cardinality attributes each for 90 seconds.
**Signal**: Grafana dashboards show gaps; OTel Collector logs show
"context deadline exceeded" and dropped spans; application stays healthy.

### 10. TLS Certificate Expiry

TLS certificate is generated with a 10-second expiry during the test window.
Clients with cached TLS sessions continue succeeding; new connections fail
with TLS handshake errors. Creates intermittent failures based on connection
cache state.

**Mechanism**: Short-lived self-signed cert expires during the test.
Proxy configured for HTTPS on port 443.
**Signal**: HTTP on port 80 works fine throughout; HTTPS on port 443 has
~50% intermittent TLS handshake failures.

---

## AI Agent Prompts

Prompt files are in `prompts/`:

```
prompts/
├── traefik/
│   ├── system-prompt.md         # Topology, URLs, agent instructions
│   └── scenarios/
│       ├── gray-failure.md      # Scenario-specific incident brief
│       └── ...
└── ferron3/
    ├── system-prompt.md
    └── scenarios/
        └── ...
```

### How to Use

1. Run `make prompt-traefik` or `make prompt-ferron3` to print the system
   prompt and available scenario prompts.
2. Concatenate the **system prompt** with the **scenario incident brief**.
3. Paste the combined prompt into your AI agent.
4. The agent investigates using the provided URLs and Grafana access.
5. Evaluate the agent's response against the evaluation criteria.

### Evaluation Criteria

Score the agent on:

1. **Root cause accuracy**: Did they identify the correct failure mechanism?
2. **Specificity**: Do they cite specific trace IDs, log lines, and metric
   queries they actually pulled (not a plausible narrative)?
3. **Layer isolation**: Did they check both proxy and backend layers?
4. **Dual-cause detection**: For stacked scenarios, did they find both
   independent issues or merge them into one incorrect narrative?

### Scenario Briefs

Each scenario brief presents the agent with symptoms to investigate — without
revealing the root cause. The briefs include:

- **Symptoms**: What the agent should observe (error rates, latency, etc.)
- **Your Task**: The investigation questions
- **Hints**: None — treat this as a real incident
- **Evidence Standard**: Minimum evidence the agent must provide

All scenario briefs require at least:
- One specific trace ID of a failed request
- One metric query showing the error rate by backend
- One log line from the affected backend showing the error
- The Grafana Explore URL or query used to find each piece of evidence

---

## Running Scenarios

Individual scenario scripts can be run standalone. Each script:
1. Starts the stack if not already running
2. Injects the failure condition
3. Runs traffic through the system
4. Cleans up

```bash
# Run a specific scenario with Traefik
make scenario-gray-failure

# Or with Ferron 3
PROXY=ferron3 make scenario-gray-failure

# All scenarios
make scenario-gray-failure          # 100% error on /error route of one backend
make scenario-latency               # Latency injection (2-5s delay)
make scenario-recovery-herd         # Circuit breaker thundering herd
make scenario-dns-poisoning         # Partial DNS pool poisoning
make scenario-timeout-mismatch      # Client < proxy < backend timeout gap
make scenario-retry-amplification   # Proxy retry amplifies errors into a storm
make scenario-circuit-breaker       # Extreme latency with no errors (cb blind spot)
make scenario-health-check          # Health check path mismatch
make scenario-observability-backpressure   # Trace flood overwhelms OTel Collector
make scenario-tls-certificate       # Expired TLS certificate
make scenario-cache-stampede        # Cache stampede
make scenario-cache-poisoning       # Cache poisoning
make scenario-cache-key-fragmentation # Cache key fragmentation
make scenario-forward-proxy-whitelist-bypass   # Forward proxy whitelist bypass
make scenario-directory-traversal   # Directory traversal
make scenario-mime-type-confusion   # MIME type confusion
make scenario-rate-limit-burst      # Rate limit burst mismatch
make scenario-recompression-corruption  # Re-compression corruption
make scenario-compression-exclusion   # Compression type exclusion
make scenario-session-ticket-restart    # Session ticket key loss on restart
make scenario-mtls-ca-missing       # mTLS CA file missing
make scenario-forwarded-auth-down   # Forwarded auth backend down
make scenario-basic-auth-concurrency  # Basic auth concurrency lockout
make scenario-trace-flood-disk      # Trace flood fills disk
make scenario-admin-api-exposed     # Admin API without auth
```

### Chaos Agents

Some scenarios require additional chaos agents (built separately):

```bash
make build-chaos-agents   # Build all agent images
make up-chaos             # Start chaos agents
```

| Agent | Purpose | Image |
|-------|---------|-------|
| `dns-poison` | DNS poisoning via dnsmasq | `dns-poison-agent` |
| `trace-mangler` | HTTP proxy that corrupts traceparent headers | `trace-mangler-agent` |
| `trace-flood` | High-cardinality OTLP trace flood generator | `trace-flood-agent` |
| `battletest-auth-backend` | Authentication backend for auth scenarios | `battletest-auth-backend` |

---

## Adding a New Proxy

1. Create `docker/docker-compose.<proxy>.yml` with the proxy service
   definition and any proxy-specific labels/config mounts.

2. If the proxy needs a config file, add it under `docker/config/<proxy>/`.

3. Create `prompts/<proxy>/system-prompt.md` with topology, URLs, and
   proxy-specific notes for the AI agent.

4. Add a `PROXY=<proxy>` target in the Makefile if needed.

---

## File Layout

```
ai-sre-new/
├── backend/                          # Enhanced Rust backend
│   ├── Cargo.toml
│   ├── Dockerfile
│   └── src/main.rs                   # 10 routes, env-var configurable
├── loadgen/                          # Rust traffic generator
│   ├── Cargo.toml
│   ├── Dockerfile
│   └── src/main.rs
├── docker/
│   ├── docker-compose.yml            # Base: backends + observability
│   ├── docker-compose.traefik.yml    # Traefik proxy + labels
│   ├── docker-compose.ferron3.yml    # Ferron 3 proxy
│   ├── docker-compose.chaos.yml      # Chaos agents
│   └── config/
│       ├── otel-collector.yaml
│       ├── tempo.yaml
│       ├── mimir.yaml
│       ├── loki.yaml
│       ├── grafana-datasources.yaml
│       ├── ferron3/
│       │   └── ferron.conf
│       └── traefik/
│           └── dynamic/
│               ├── retry.yml
│               ├── circuit-breaker.yml
│               ├── health-check.yml
│               └── tls.yml
├── chaos/
│   ├── lib/
│   │   ├── docker.sh                 # Docker helper functions
│   │   └── traffic.sh                # Traffic generation helpers
│   ├── scenarios/
│   │   ├── gray-failure.sh
│   │   ├── latency-injection.sh
│   │   ├── recovery-herd.sh
│   │   ├── dns-poisoning.sh
│   │   ├── timeout-mismatch.sh
│   │   ├── retry-amplification.sh
│   │   ├── circuit-breaker-blind-spot.sh
│   │   ├── health-check-manipulation.sh
│   │   ├── observability-backpressure.sh
│   │   └── tls-certificate-mismatch.sh
│   └── agents/
│       ├── dns-poison/               # DNS poisoning container
│       ├── trace-mangler/            # Trace header corruption proxy
│       └── trace-flood/              # High-cardinality trace flood
├── prompts/
│   ├── traefik/
│   │   ├── system-prompt.md
│   │   └── scenarios/
│   └── ferron3/
│       ├── system-prompt.md
│       └── scenarios/
├── Makefile
└── README.md
```

---

## Environment Variables

### Backend (per-instance)

| Variable | Default | Description |
|----------|---------|-------------|
| `LATENCY_MS` | `0` | Global latency added to every request (ms) |
| `ERROR_PCT` | `0.0` | Probability of returning an error (0.0–1.0) |
| `ERROR_CODE` | `500` | HTTP status code for injected errors |
| `TRACE_CORRUPT_PCT` | `0.0` | Probability of corrupting traceparent response |
| `HEALTHY` | `true` | Whether `/health` returns 200 |
| `CORRUPT_RESPONSE_PCT` | `0.0` | Probability of corrupting response body bytes |
| `MISMATCH_CONTENT_LENGTH` | `false` | If true, set wrong Content-Length |

### Backend Routes

| Route | Method | Description |
|-------|--------|-------------|
| `/` | GET | Root — injects latency and errors per env vars |
| `/health` | GET | Health check — respects `HEALTHY` env var |
| `/slow/{ms}` | GET | Sleeps for `{ms}` ms with optional `?jitter=` |
| `/echo` | POST | Echoes request body |
| `/large/{bytes}` | GET | Returns `{bytes}` random bytes |
| `/headers` | GET | Echoes request headers |
| `/error` | GET | Returns error per `?pct=` and `?code=` params |
| `/race` | GET | Thundering herd test with optional `?delay_ms=` |
| `/trace` | GET | Returns trace headers (with optional corruption) |
| `/stream/{ms}` | GET | SSE-style stream sending heartbeats every 500ms |

### Trace-flood Agent

| Variable | Default | Description |
|----------|---------|-------------|
| `SPAN_RATE` | `10000` | Spans per second to generate |
| `OTLP_ENDPOINT` | `http://otel-collector:4317` | OTLP gRPC endpoint |
| `DURATION_SECS` | `90` | How long to run |
| `CARDINALITY` | `20` | High-cardinality attributes per span |

### Load Generator

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_URL` | `http://proxy:80` | Base URL to target |
| `RATE` | `10` | Requests per second |
| `DURATION_SECS` | `30` | How long to run |
| `TIMEOUT_SECS` | `30` | HTTP client timeout per request |
| `CONCURRENCY` | `5` | Concurrent connections |
| `METHOD` | `GET` | HTTP method |
| `REQUEST_PATH` | `/` | URL path |
| `BODY_SIZE` | `0` | Request body size for POST (bytes) |
| `HEADERS` | `` | Comma-separated `Key:Value` pairs |
| `VALIDATE_CONTENT_LENGTH` | `false` | Check Content-Length matches body |
| `VALIDATE_STATUS` | `200` | Expected HTTP status code |
| `OUTPUT_JSON` | `false` | JSON output format |

---

## About This Project

This harness was scaffolded using an AI agent — the architecture, failure
scenarios, and battle-test design were manually reviewed and approved, while
boilerplate code and repetitive scaffolding were offloaded to AI. This means:

- **The architecture and failure scenarios are solid.** The topology, OTel
  integration, and scenario logic were designed and validated by hand.
- **There may be rough edges.** Shell scripts, config files, and boilerplate
  may have syntax quirks or minor issues. Feel free to submit PRs to clean
  those up.

If you find a rough edge or have a suggestion, please open an issue or
submit a PR — the community is welcome to help polish the implementation.

---

## Extending

### Adding a backend route

Edit `backend/src/main.rs`, add a handler function and register it in the
`Router`. Rebuild with `make rebuild`.

### Adding a scenario

1. Create `chaos/scenarios/<name>.sh` using the shared helpers from
   `chaos/lib/docker.sh` and `chaos/lib/traffic.sh`
2. Add a `make` target in the Makefile
3. Create a corresponding prompt file in `prompts/<proxy>/scenarios/`

### Adding a chaos agent

1. Create a directory under `chaos/agents/<name>/` with the agent code
   and Dockerfile
2. Add the service to `docker/docker-compose.chaos.yml`
3. Reference it from scenario scripts as needed
