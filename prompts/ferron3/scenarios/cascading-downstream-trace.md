# Incident: Downstream Dependency Bottleneck — Trace Shows Backend as Slow

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- One backend shows significantly higher latency than others
- No errors — all requests return 200 OK
- Backend-1 has 2s latency while backends 2-3 are fast
- Traces show backend-1 span taking ~2s
- The real bottleneck is downstream of the backend, not the backend itself

## Your Task

Investigate this incident. Determine:

1. Is the backend itself slow, or is its downstream dependency slow?
2. How does W3C Trace Context propagation help identify the real bottleneck?
3. What trace attributes would show the downstream dependency?
4. How can you distinguish "backend is slow" from "backend's dependency is slow"?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Trace showing backend-1 span with ~2s latency
- Trace context propagation via `traceparent` header
- Ferron proxy span attributes showing `ferron.proxy.backend_url`
- A Grafana Explore URL showing the span hierarchy
- Analysis of whether the bottleneck is the backend or its downstream
