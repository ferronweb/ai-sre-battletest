# Incident: OpenTelemetry Collector Unreachable — Observability Events Dropped

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- All application traffic appears healthy (200 OK, normal latency)
- Ferron proxy metrics show `observability_event_queue_len` increasing rapidly
- `observability_events_dropped` counter is non-zero
- No traces, logs, or metrics are arriving in Grafana dashboards
- OTel collector container is unhealthy or unreachable

## Your Task

Investigate this incident. Determine:

1. Why are observability events being dropped?
2. Is the OTel collector actually down, or is there a network issue?
3. What happens to in-flight requests when the collector is unreachable?
4. How can you detect this condition without relying on the observability stack itself?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Ferron admin API status showing `observability_events_dropped > 0`
- Ferron admin API status showing `observability_event_queue_len > 0`
- OTel collector container status (unhealthy or stopped)
- A metric query or log line confirming the collector is unreachable
- The Grafana Explore URL or query used to find each piece of evidence

## Lightweight Mode Notes

**This scenario is NOT applicable in lightweight mode.**

The lightweight profile does not include an OpenTelemetry Collector, so this scenario cannot occur. The observability pipeline queue backup scenario requires:
- OTel Collector running and configured
- OTLP export from Ferron to the collector
- Collector becoming unreachable or overloaded

In lightweight mode, Ferron either:
- Exports metrics directly via Prometheus (no OTLP)
- Has no metrics export at all (logs-only profile)

Therefore, this scenario should be skipped when testing in lightweight mode.
