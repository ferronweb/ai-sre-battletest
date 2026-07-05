# Incident: Extreme Latency with Zero Errors

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Users report the application is very slow, but no errors are visible
- p50 latency is near-normal, but p99 latency has spiked dramatically
- The circuit breaker is green (no errors recorded)
- No 5xx errors at all across the system
- Health checks are green on all backends

## Your Task

Investigate this incident. Determine:

1. What is causing the latency spike?
2. Which backend(s) are affected?
3. Why didn't the circuit breaker activate?
4. What configuration change would have caught this issue?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A latency percentile comparison (p50 vs p99) showing the spike
- A metric query showing latency by backend
- A circuit breaker state query showing it never opened
- The Grafana Explore URL or query used to find each piece of evidence
