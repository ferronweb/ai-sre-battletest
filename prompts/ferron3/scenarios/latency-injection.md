# Incident: Latency Spike with No Errors

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Users report the application feels slow, but no errors are visible
- p50 latency is still near-normal
- p99 latency has spiked dramatically
- No 5xx errors, no alerts have fired
- Health checks are green on all backends

## Your Task

Investigate this incident. Determine:

1. What is causing the latency spike?
2. Which backend(s) are affected?
3. Why didn't any alerts fire?
4. What is the p99 latency compared to the baseline?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A latency percentile comparison (p50 vs p99) showing the spike
- A metric query showing latency by backend
- A trace showing the slow request path
- The Grafana Explore URL or query used to find each piece of evidence

## Lightweight Mode Notes

When running in lightweight mode (without Grafana, Loki, Tempo, Mimir):

### Available Signals
- **Logs**: Use `docker logs proxy`, `docker logs backend-1`, etc. to access JSON logs
- **Metrics**: Use `curl http://localhost:8889/metrics | grep ferron` for Prometheus metrics (logs+prometheus profile only)
- **Admin API**: Use `curl http://localhost:8081/status` for server status

### Adapted Evidence Collection
- **Latency percentiles**: Query Prometheus histogram metrics:
  ```bash
  # Get request duration histogram
  curl -s http://localhost:8889/metrics | grep 'ferron.http.server.request.duration'
  
  # Calculate p99 from histogram buckets
  curl -s http://localhost:8889/metrics | grep 'ferron.http.server.request.duration_bucket' | \
    awk -F'le=' '{print $2}' | awk '{sum+=$1} END {print "p99 threshold: " sum}'
  ```
  Or parse logs for slow requests:
  ```bash
  docker logs proxy --since 1m 2>&1 | jq 'select(.duration_secs > 1.0)'
  ```
- **Latency by backend**: Check backend-specific logs:
  ```bash
  docker logs backend-1 --since 1m 2>&1 | jq 'select(.duration > 1000)'
  ```
- **Trace showing slow path**: Not available in lightweight mode. Use log timestamps to correlate slow requests.
- **Grafana URL**: Not available. Use CLI commands instead.

### Limitations
- No distributed traces (cannot see full request path across services)
- No pre-built latency dashboards (must calculate percentiles manually)
- No centralized log aggregation (must query each container separately)
