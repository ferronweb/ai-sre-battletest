# Incident: Rate Limit Bypass via Forward Proxy

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Some clients are rate-limited (429 responses)
- Other clients bypass rate limits entirely
- Abuse protection shows bans for some IPs but not others
- The bypass correlates with requests appearing to come from 127.0.0.1
- Forward proxy is configured on the server

## Your Task

Investigate this incident. Determine:

1. Why are some clients bypassing rate limits?
2. How does the forward proxy affect client IP detection?
3. What is the relationship between the whitelist and the bypass?
4. How would you fix this without disabling the forward proxy?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A rate-limited response with X-Forwarded-For header
- An unbanned request appearing to come from 127.0.0.1
- The abuse protection whitelist configuration
- The Grafana Explore URL or query used to find each piece of evidence
