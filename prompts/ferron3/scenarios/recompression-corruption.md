# Incident: Corrupt Responses for Compressed Assets

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Some responses contain garbage/corrupt data
- Content-Encoding header shows zstd or br
- But the actual body is not valid compressed data
- Issue affects pre-compressed files specifically
- Normal uncompressed responses work fine

## Your Task

Investigate this incident. Determine:

1. Why are compressed responses corrupt?
2. What is the relationship between pre-compressed files and re-compression?
3. How does Cache-Control affect compression behavior?
4. How would you fix this without disabling compression?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A corrupt response with wrong Content-Encoding
- Evidence of pre-compressed file being re-compressed
- The compression configuration
- The Grafana Explore URL or query used to find each piece of evidence
