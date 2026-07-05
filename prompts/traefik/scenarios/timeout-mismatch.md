# Incident: Cascading Timeouts with No Obvious Error Source

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- Load generator reports connection timeouts (~1s)
- The proxy sees connections opened and then abandoned
- Backend eventually responds but the response is discarded
- No single layer has a complete picture — each layer sees a different symptom
- Request rate at the proxy has doubled compared to baseline (due to retries)

## Your Task

Investigate this incident. Determine:

1. What is causing the initial timeout?
2. Why are retries doubling the load at the proxy?
3. What is the timeout configuration at each layer (client, proxy, backend)?
4. What is the root cause — is it a timeout mismatch or a backend issue?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A trace showing the abandoned request path across layers
- A metric showing retry rate at the load generator
- A metric showing timeout rate at the proxy
- The Grafana Explore URL or query used to find each piece of evidence
