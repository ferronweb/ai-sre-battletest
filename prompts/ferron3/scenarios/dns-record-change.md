# Incident: Backend Container Recreated with New IP — DNS Cache Stale

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- Some requests fail with connection refused or timeout
- Other requests succeed normally
- Backend-1 was recently restarted (container recreation)
- DNS resolution shows different IPs for the same hostname
- Ferron proxy metrics show DNS cache miss events

## Your Task

Investigate this incident. Determine:

1. Why are some requests failing after a backend restart?
2. How does Ferron handle DNS changes for upstream backends?
3. What metrics show DNS cache behavior (hits vs misses)?
4. How long does it take for Ferron to detect a DNS change?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Ferron admin API status showing `dns.cache_miss` events
- DNS resolution showing different IPs before and after restart
- Request failures correlated with the DNS change timing
- A metric query showing DNS cache hit/miss ratio
- The Grafana Explore URL or query used to find each piece of evidence
