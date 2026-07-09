# Incident: Connection Pool Exhaustion — Fast Requests Blocked by Slow Route

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Some requests complete instantly, others take 5-10 seconds
- No backend errors — all responses are 200 OK
- p50 latency is low, but p99 latency is extremely high
- Backend health checks pass on all instances
- Ferron proxy shows `connections_active` very high (close to pool limit)

## Your Task

Investigate this incident. Determine:

1. Why are fast requests being blocked?
2. What is the connection pool configuration per upstream?
3. How many concurrent slow requests are holding connections open?
4. What metric would indicate pool exhaustion before users notice?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Ferron admin API status showing high `connections_active`
- A query showing the pool limit configuration (`limit 5` per upstream)
- Metric showing requests waiting for pool connections
- A Grafana Explore URL or query showing connection pool wait times
- The difference in latency between requests hitting the slow route vs fast route
