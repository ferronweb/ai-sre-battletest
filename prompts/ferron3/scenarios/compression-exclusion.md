# Incident: HTML Pages Not Compressed

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- HTML page load times increased significantly
- API responses (JSON) are compressed normally
- Browser shows uncompressed HTML responses
- No errors visible — content is correct, just slow
- Compression appears to work for some content types but not others

## Your Task

Investigate this incident. Determine:

1. Why are HTML pages not compressed?
2. Which content types ARE compressed?
3. What configuration change caused this selective compression failure?
4. How would you fix the compression configuration?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A response showing missing Content-Encoding header for HTML
- A response showing correct Content-Encoding for JSON/CSS
- The compression type list from the proxy config
- The Grafana Explore URL or query used to find each piece of evidence
