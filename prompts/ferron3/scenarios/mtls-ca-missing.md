# Incident: Complete Outage After TLS Configuration Change

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- All requests fail with connection errors
- Health checks from outside the proxy fail
- No backend errors visible (backends are healthy)
- The issue started immediately after a TLS configuration change
- curl shows TLS handshake failures

## Your Task

Investigate this incident. Determine:

1. Why are all TLS connections failing?
2. Is this a certificate issue, a CA issue, or a client auth issue?
3. What specific configuration change caused the outage?
4. How would you fix this without disabling TLS entirely?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One TLS handshake error from logs
- The specific misconfigured field in the TLS config
- Evidence that backends are healthy (separate from proxy)
- The Grafana Explore URL or query used to find each piece of evidence
