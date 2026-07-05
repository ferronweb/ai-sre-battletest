# Incident: Backend Overload After Cache Expiry

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Backend request rate spiked from ~50/s to ~300/s
- p99 latency increased dramatically
- Backend CPU usage is high
- No errors visible — all requests eventually succeed
- Cache hit rate dropped to 0% during the spike

## Your Task

Investigate this incident. Determine:

1. What caused the sudden spike in backend requests?
2. Why did the cache hit rate drop to 0%?
3. What is the relationship between cache expiry and the traffic spike?
4. How would you prevent this thundering herd in the future?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A metric query showing the backend request rate spike
- A cache hit rate metric showing the drop
- A latency percentile comparison during the spike
- The Grafana Explore URL or query used to find each piece of evidence
