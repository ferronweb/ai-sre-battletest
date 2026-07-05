# Incident: Template Files Downloaded Instead of Rendered

## Duration

Ongoing for approximately 60 seconds.

## Symptoms

- Users report .tmpl files download instead of rendering in browser
- HTML files render correctly
- Content-Type header shows application/octet-stream for .tmpl files
- No errors visible — content is correct, just wrong MIME type
- Browser behavior changed for template files

## Your Task

Investigate this incident. Determine:

1. Why are .tmpl files served with the wrong MIME type?
2. What Content-Type should .tmpl files have?
3. How does the MIME type affect browser behavior?
4. How would you fix the MIME type configuration?

## Hints

None — treat this as a real incident.

## Evidence Standard

Your response must include at least:
- A response showing Content-Type: application/octet-stream for .tmpl
- A response showing correct Content-Type for .html files
- The MIME type configuration (or lack thereof)
- The Grafana Explore URL or query used to find each piece of evidence
