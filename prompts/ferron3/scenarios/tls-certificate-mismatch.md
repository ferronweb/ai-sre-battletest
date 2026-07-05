# Incident: Intermittent TLS Handshake Failures

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- HTTP on port 80 works perfectly
- HTTPS on port 443 has intermittent failures (~50% failure rate)
- Some HTTPS connections succeed, others fail with TLS handshake errors
- No backend errors — backends are healthy
- The application itself is responding correctly when connections succeed

## Your Task

Investigate this incident. Determine:

1. Why are HTTPS connections intermittently failing?
2. Why do some connections succeed while others fail?
3. What is the root cause of the TLS handshake failures?
4. How would you fix the issue?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- The certificate expiry date and issuer
- A TLS handshake failure log or metric
- The proxy TLS configuration showing any misconfiguration
- The Grafana Explore URL or query used to find each piece of evidence
