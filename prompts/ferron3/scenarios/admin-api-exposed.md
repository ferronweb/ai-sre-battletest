# Incident: Intermittent Latency Spikes After Config Reloads

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- Intermittent latency spikes (p99 jumps to 500ms+)
- Cache hit rate drops to 0% periodically
- Health checks are green
- No application errors visible
- Spikes correlate with admin API access in logs

## Your Task

Investigate this incident. Determine:

1. What is causing the periodic cache flushes?
2. Who or what is triggering the config reloads?
3. Why is the admin API accessible without authentication?
4. What security risk does this expose?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One log line showing admin API reload access
- A metric query showing cache hit rate dropping
- The admin API endpoint that was accessed (POST /reload)
- The Grafana Explore URL or query used to find each piece of evidence
