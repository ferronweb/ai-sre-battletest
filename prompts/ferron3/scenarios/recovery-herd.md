# Incident: Sudden Spike in 502 Errors After Backend Recovery

## Duration

Ongoing for approximately 30 seconds.

## Symptoms

- A sudden burst of 502 errors appeared after a backend was restarted
- The error rate spiked to ~30% then is slowly decreasing
- The backend that was restarted is now healthy
- Other backends are also showing elevated latency during the spike
- No alerts fired during the error burst

## Your Task

Investigate this incident. Determine:

1. What caused the sudden error burst?
2. Is this related to the backend recovery, or a separate issue?
3. Why are the other backends also showing elevated latency?
4. What is the expected recovery trajectory?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A metric showing error rate over time around the recovery event
- A trace showing requests hitting the recovering backend
- A metric showing backend latency during the recovery window
- The Grafana Explore URL or query used to find each piece of evidence
