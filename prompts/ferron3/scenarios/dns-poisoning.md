# Incident: Intermittent Connection Timeouts

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Users report occasional connection timeouts on the application
- Error rate is intermittent, not consistent across all backends
- Some requests succeed while others fail with timeout errors
- No alerts have fired — the error rate is low enough to evade threshold-based alerts
- Health checks are green on all backends

## Your Task

Investigate this incident. Determine:

1. Which backend(s) are experiencing timeouts?
2. Is this a network issue, a backend issue, or a proxy issue?
3. Why are health checks not reflecting the issue?
4. What is the actual timeout rate for the affected backend?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A metric showing error rate by backend
- A trace showing the timeout path
- A log line from the affected backend or proxy showing the timeout
- The Grafana Explore URL or query used to find each piece of evidence
