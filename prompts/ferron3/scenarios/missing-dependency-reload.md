# Incident: Referenced Upstream Removed — Config References Missing Backend

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- Ferron config references a backend that no longer exists
- Some requests succeed (to remaining backends), some may fail
- Ferron is still healthy and serving traffic
- The missing backend was recently removed from the infrastructure
- Reload was triggered after the backend was removed

## Your Task

Investigate this incident. Determine:

1. Which backend is missing from the infrastructure?
2. How does Ferron handle a missing upstream after reload?
3. What errors or warnings appear in logs or admin API?
4. How can you distinguish "one backend missing" from "all backends down"?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Ferron config showing the missing backend (backend-4)
- Ferron health check still returning 200
- Admin API status showing active connections to remaining backends
- Logs or metrics showing errors related to the missing backend
- The Grafana Explore URL or query used to find each piece of evidence
