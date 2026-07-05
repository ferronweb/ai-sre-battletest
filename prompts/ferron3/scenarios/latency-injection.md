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
