# Incident: Errors Persist After Backend Recovery

## Duration

Ongoing for approximately 60 seconds after backend recovery.

## Symptoms

- Error rate remains high even though all backends are healthy
- Cache hit rate is high (cache is working)
- But cached responses contain errors
- The issue started when one backend was returning errors
- Even after backend recovery, errors continue

## Your Task

Investigate this incident. Determine:

1. Why are errors persisting after backend recovery?
2. What is the relationship between cache hit rate and error rate?
3. Which responses are being cached — successes or errors?
4. How would you fix this without disabling the cache entirely?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A metric query showing high cache hit rate AND high error rate
- Evidence that cached responses contain errors
- The cache TTL that's causing the persistence
- The Grafana Explore URL or query used to find each piece of evidence
