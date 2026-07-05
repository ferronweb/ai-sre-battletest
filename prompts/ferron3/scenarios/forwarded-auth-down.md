# Incident: Complete Outage When Auth Service Is Down

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- All requests fail with 502 or 503 errors
- Health checks from outside the proxy fail
- Backend health checks are green
- The issue started when the auth service went down
- No fallback authentication mechanism exists

## Your Task

Investigate this incident. Determine:

1. Why are all requests failing when backends are healthy?
2. What is the relationship between the auth service and the proxy?
3. Why is there no fallback authentication?
4. How would you prevent this single point of failure?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One error response showing auth service unavailability
- Evidence that backends are healthy
- The auth service configuration in the proxy
- The Grafana Explore URL or query used to find each piece of evidence
