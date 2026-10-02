# Changelog

## v1.1.0 (2026-10-02)

- **Deep Site Audit**: new `deep-audit` input (plus `deep-audit-business-type`,
  `deep-audit-timeout`, `deep-audit-fail-on-high`, `deep-audit-base-url`). Runs on the main
  host, `https://seoscoreapi.com` (`POST /site-audit`, polls `GET /site-audit/{job_id}`),
  retries on queue backpressure, writes the score and top findings to the job summary.
  New outputs `deep-audit-score`, `deep-audit-grade`, `deep-audit-high-findings`,
  `deep-audit-job-id`, `deep-audit-remaining` (quota left, from `GET /deep-audit/usage`).
  A poll answering 401/403/404 fails at once instead of retrying until the timeout. Script: `scripts/deep-audit.sh`; tests: `bash test/test-deep-audit.sh`.
- Fix: outputs (`score`, `grade`, `issues`, `report-url`) were declared without `value:`,
  which composite actions require, so they were always empty to the calling workflow.
- Fix: `fail-on-threshold` never failed the build. Scores are decimals (e.g. `97.56`) and
  `[ "$SCORE" -lt "$THRESHOLD" ]` errored instead of comparing; it now compares numerically.
- Inputs reach the shell through `env:` instead of being pasted into the script, and the URL
  is URL-encoded on the request.

## v1

- First release: audit a URL, fail below a threshold, job summary.
