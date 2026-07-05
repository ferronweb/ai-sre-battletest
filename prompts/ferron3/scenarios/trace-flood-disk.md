# Incident: Observability Pipeline Overwhelmed

## Duration

Ongoing for approximately 90 seconds.

## Symptoms

- Grafana dashboards show data gaps in traces and metrics
- Application `/health` endpoints remain 200
- Users report no visible errors in the application
- Trace logs are filling disk rapidly
- No application-level alerts have fired

## Your Task

Investigate this incident. Determine:

1. Why are Grafana dashboards showing data gaps?
2. Is the application actually down, or is the observability pipeline overwhelmed?
3. What is the root cause of the trace log volume spike?
4. How would you fix this without losing observability entirely?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One metric query showing trace log volume or disk usage
- One log line showing trace export failures or backpressure
- A Grafana dashboard panel showing the data gaps
- The Grafana Explore URL or query used to find each piece of evidence
