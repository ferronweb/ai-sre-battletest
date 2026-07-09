# Incident: Intermittent Errors on /error Route

## Duration

Ongoing for approximately 30 minutes.

## Symptoms

- Users report occasional 500 errors when accessing the `/error` endpoint
- The `/health` endpoint always returns 200
- Overall error rate appears low (< 1%)
- No alerts have fired

## Your Task

Investigate this incident. Determine:

1. What is the root cause of the intermittent 500 errors?
2. Which backend(s) are affected?
3. Why is the health check not reflecting the issue?
4. What is the actual error rate for the affected route?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One specific trace ID of a failed request
- One metric query showing the error rate by backend
- One log line from the affected backend showing the error
- The Grafana Explore URL or query used to find each piece of evidence

## Lightweight Mode Notes

When running in lightweight mode (without Grafana, Loki, Tempo, Mimir):

### Available Signals
- **Logs**: Use `docker logs proxy`, `docker logs backend-1`, etc. to access JSON logs
- **Metrics**: Use `curl http://localhost:8889/metrics | grep ferron` for Prometheus metrics (logs+prometheus profile only)
- **Admin API**: Use `curl http://localhost:8081/status` for server status

### Adapted Evidence Collection
- **Trace ID**: Not available in lightweight mode (no distributed tracing). Focus on log correlation instead.
- **Error rate by backend**: Query Prometheus metrics:
  ```bash
  curl -s http://localhost:8889/metrics | grep 'ferron.http.server.request.count.*status="500"'
  ```
  Or parse logs:
  ```bash
  docker logs proxy --since 5m 2>&1 | jq 'select(.status == 500)'
  ```
- **Log lines**: Use `docker logs backend-1 --since 30m 2>&1 | grep error`
- **Grafana URL**: Not available. Use CLI commands instead.

### Limitations
- No distributed traces (cannot correlate across services)
- No centralized log aggregation (must query each container separately)
- No pre-built dashboards (must use CLI tools)
