# Incident: Cache Hit Rate Drop with Diverse Cookies

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Cache hit rate dropped from ~95% to ~10%
- Backend request rate increased proportionally
- p50 latency increased slightly
- No errors visible — all requests succeed
- The issue correlates with diverse cookie values

## Your Task

Investigate this incident. Determine:

1. Why did the cache hit rate drop so dramatically?
2. How do cookies affect cache key generation?
3. What configuration change would fix this?
4. How would you balance cookie diversity with cache efficiency?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A cache hit rate metric showing the drop
- Evidence of cookie diversity in request logs
- The cache configuration showing include cookies setting
- The Grafana Explore URL or query used to find each piece of evidence
