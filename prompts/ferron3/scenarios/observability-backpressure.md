# Incident: Grafana Dashboards Showing Data Gaps

## Duration

Ongoing for approximately 90 seconds.

## Symptoms

- Grafana dashboards have gaps or stale data
- Tempo trace queries are slow or fail
- Mimir ingestion lag is increasing
- Loki logs have gaps
- The application /health endpoint returns 200
- No backend errors or latency

## Your Task

Investigate this incident. Determine:

1. Why is telemetry data missing from Grafana?
2. Is the application actually down or just the observability pipeline?
3. What is causing the observability pipeline to fail?
4. How would you fix or mitigate the issue?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A Grafana panel showing the data gap period
- An OTel Collector log line showing dropped spans or errors
- A successful /health check during the gap period
- The Grafana Explore URL or query used to find each piece of evidence
