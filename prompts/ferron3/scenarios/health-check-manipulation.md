# Incident: Intermittent Errors on Long-Lived Connections

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Long-lived streaming connections intermittently fail with 503 errors
- The /health endpoint always returns 200 (proxy sees backends as healthy)
- Error rate is moderate (~40% of requests hitting the affected backend)
- No alerts have fired — the proxy's health check is green

## Your Task

Investigate this incident. Determine:

1. What is causing the intermittent 503 errors?
2. Which backend(s) are affected?
3. Why is the proxy's health check not reflecting the issue?
4. What is the actual error rate for the affected backend?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One specific trace ID of a failed request
- One metric query showing the error rate by backend
- One log line from the affected backend showing the error
- The Grafana Explore URL or query used to find each piece of evidence
