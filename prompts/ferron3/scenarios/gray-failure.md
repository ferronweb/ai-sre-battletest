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
