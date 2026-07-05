# Incident: Users Locked Out Behind NAT

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Some users get 403 Forbidden responses
- Other users on the same network work fine
- No brute-force protection triggered
- Authentication credentials are correct
- Issue correlates with number of concurrent connections

## Your Task

Investigate this incident. Determine:

1. Why are some users getting 403 while others succeed?
2. What is the relationship between concurrent connections and the 403s?
3. How does concurrency limiting work with shared IP addresses?
4. How would you fix this for users behind NAT?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A 403 response with concurrency-related error message
- The basic auth configuration showing concurrency limit
- Evidence of multiple users sharing an IP address
- The Grafana Explore URL or query used to find each piece of evidence
