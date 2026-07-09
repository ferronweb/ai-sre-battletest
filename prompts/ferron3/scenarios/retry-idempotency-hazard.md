# Incident: Duplicate Processing on Idempotent Operations

## Duration

Ongoing for approximately 10 seconds.

## Symptoms

- POST requests to `/post-count` show a count significantly higher than expected
- Only 5 requests were sent, but the counter shows 100+ increments
- No errors in logs — all requests return 200 OK
- Retry configuration is enabled on the proxy
- Backend logs show repeated processing of the same logical request

## Your Task

Investigate this incident. Determine:

1. Why are idempotent POST requests being processed multiple times?
2. Is the proxy retrying failed requests, or is there another cause?
3. What is the retry configuration on the proxy?
4. How would you fix this in production without disabling retries entirely?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- The expected vs actual POST count (e.g., 5 sent vs 227 processed)
- Ferron proxy retry configuration (connection_timeout, retry settings)
- Backend logs showing duplicate request processing
- A metric query showing retry behavior
- The Grafana Explore URL or query used to find each piece of evidence
