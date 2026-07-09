# Incident: Emergency Config Fix Not in Version Control

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- An emergency fix was applied to fix an incident
- The fix is working (custom header visible in responses)
- The fix was applied by editing the config file directly
- The fix was never committed to version control
- A subsequent deploy would overwrite the fix

## Your Task

Investigate this incident. Determine:

1. How was the emergency fix applied?
2. Is the fix committed to version control?
3. How can you detect config drift between running and committed configs?
4. What is the reload generation count and what does it mean?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- Ferron admin API reload state showing `active_generation > 0`
- Config file content showing the emergency fix
- Verification that the fix is active in responses
- A comparison of running config vs committed config
- The Grafana Explore URL or query used to find each piece of evidence
