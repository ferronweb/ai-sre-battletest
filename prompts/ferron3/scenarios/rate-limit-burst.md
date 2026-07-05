# Incident: 429 Errors During SPA Loading

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Users see broken pages with missing assets
- 429 (Too Many Requests) responses visible in network tab
- Rate limit headers show burst limit exceeded
- Normal browsing works fine
- Issue only occurs during rapid asset loading

## Your Task

Investigate this incident. Determine:

1. Why are legitimate asset requests being rate-limited?
2. What is the relationship between burst size and SPA loading patterns?
3. How would you fix this without removing rate limiting entirely?
4. What rate limit configuration would accommodate SPA loading?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A 429 response with rate limit headers
- The rate limit configuration showing burst size
- Evidence of rapid asset loading pattern
- The Grafana Explore URL or query used to find each piece of evidence
