# Incident: Request Rate Spike and Backend Overload

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Backend request rate is 3x higher than the client send rate
- Backend-3 is overwhelmed by request volume despite being healthy
- Intermittent 503 errors from backend-1 and backend-2
- Over 80% of requests hitting backend-1 fail
- Client success rate is low despite backend-3 being healthy

## Your Task

Investigate this incident. Determine:

1. What is causing the request amplification?
2. What proxy configuration is responsible?
3. Why is backend-3 overloaded even though it's healthy?
4. How would you fix the configuration?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A metric query showing the proxy vs backend request rate ratio
- A specific trace ID showing a retry attempt after a 503 failure
- The retry configuration that is causing the amplification
- The Grafana Explore URL or query used to find each piece of evidence
