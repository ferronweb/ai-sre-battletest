# Incident: Latency Spike After Proxy Restart

## Duration

Ongoing for approximately 60 seconds after a proxy restart.

## Symptoms

- Latency spiked immediately after a proxy restart
- p50 latency increased from ~30ms to ~200ms
- p99 latency increased from ~100ms to ~2s
- No errors visible — all requests eventually succeed
- Health checks are green on all backends

## Your Task

Investigate this incident. Determine:

1. What caused the latency spike after the restart?
2. Why didn't the latency return to baseline immediately?
3. What TLS mechanism was lost during the restart?
4. How long should the recovery take?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A latency percentile comparison showing the spike timing
- A metric query showing the latency profile over time
- Evidence of TLS handshake activity post-restart
- The Grafana Explore URL or query used to find each piece of evidence
