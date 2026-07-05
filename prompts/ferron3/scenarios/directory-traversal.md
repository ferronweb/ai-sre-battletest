# Incident: Files Accessible Outside Web Root

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Some requests return unexpected file contents
- Path traversal sequences in URLs may succeed
- Access logs show unusual URL patterns
- No application errors visible
- Static file serving is enabled

## Your Task

Investigate this incident. Determine:

1. Are files accessible outside the intended web root?
2. What URL patterns allow directory traversal?
3. Is URL sanitization enabled or disabled?
4. What security risk does this expose?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- One log line showing a path traversal attempt
- Evidence of file contents returned from outside web root
- The static file configuration showing sanitization settings
- The Grafana Explore URL or query used to find each piece of evidence
