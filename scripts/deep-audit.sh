#!/usr/bin/env bash
# Deep Site Audit for the SEO Audit Action.
# Starts POST {base}/site-audit, polls GET {base}/site-audit/{job_id} until it
# completes, reads the quota left (GET {base}/deep-audit/usage), writes outputs
# + a job summary. Inputs come from the environment:
#   SSA_URL, SSA_API_KEY            required
#   SSA_BASE_URL                    default https://seoscoreapi.com
#   SSA_BUSINESS_TYPE               optional (saas | local_service | ecommerce | ...)
#   SSA_TIMEOUT                     seconds, default 600
#   SSA_POLL_INTERVAL               seconds, default 10
#   SSA_FAIL_ON_HIGH                "true" -> exit 1 when any high/critical finding
#   GITHUB_OUTPUT, GITHUB_STEP_SUMMARY (set by Actions; default /dev/null)
set -euo pipefail

BASE="${SSA_BASE_URL:-https://seoscoreapi.com}"
BASE="${BASE%/}"
TIMEOUT="${SSA_TIMEOUT:-600}"
POLL="${SSA_POLL_INTERVAL:-10}"
OUT="${GITHUB_OUTPUT:-/dev/null}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
: "${SSA_URL:?url is required}"
: "${SSA_API_KEY:?api-key is required}"

deadline=$(( $(date +%s) + TIMEOUT ))
body=$(jq -cn --arg url "$SSA_URL" --arg bt "${SSA_BUSINESS_TYPE:-}" \
  '{url: $url} + (if $bt != "" then {business_type: $bt} else {} end)')

tmp=$(mktemp)
hdr=$(mktemp)
trap 'rm -f "$tmp" "$hdr"' EXIT

# Start the job, retrying on queue backpressure (429 + Retry-After).
while :; do
  code=$(curl -sS -o "$tmp" -D "$hdr" -w '%{http_code}' -X POST "$BASE/site-audit" \
    -H "X-API-Key: $SSA_API_KEY" -H "Content-Type: application/json" \
    -H "User-Agent: seo-audit-action/1.1.0" -d "$body") || code=000
  if [ "$code" = "429" ]; then
    retry=$(awk -F': *' 'tolower($1)=="retry-after"{gsub("\r","",$2); print $2}' "$hdr")
    retry=${retry:-30}
    if [ $(( $(date +%s) + ${retry%.*} )) -gt "$deadline" ]; then
      echo "::error::Deep audit: timed out waiting for queue capacity"
      exit 1
    fi
    echo "Deep audit queue is full; retrying in ${retry}s"
    sleep "$retry"
    continue
  fi
  if [ "$code" != "200" ] && [ "$code" != "202" ]; then
    detail=$(jq -r '.detail // empty' "$tmp" 2>/dev/null || true)
    echo "::error::Deep audit could not start (HTTP $code): ${detail:-no detail}"
    exit 1
  fi
  break
done

job_id=$(jq -r '.job_id' "$tmp")
echo "deep-audit-job-id=$job_id" >> "$OUT"
echo "Deep audit job $job_id queued"

# Poll to completion.
while :; do
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "::error::Deep audit $job_id did not finish within ${TIMEOUT}s"
    exit 1
  fi
  sleep "$POLL"
  code=$(curl -sS -o "$tmp" -w '%{http_code}' "$BASE/site-audit/$job_id" \
    -H "X-API-Key: $SSA_API_KEY" -H "User-Agent: seo-audit-action/1.1.0") || code=000
  case "$code" in
    200) ;;
    401|403|404)
      echo "::error::Deep audit poll for $job_id failed (HTTP $code): $(jq -r '.detail // "no detail"' "$tmp" 2>/dev/null || echo "no detail")"
      exit 1 ;;
    *) echo "Deep audit poll returned HTTP $code; retrying"; continue ;;
  esac
  status=$(jq -r '.status' "$tmp")
  case "$status" in
    completed) break ;;
    failed)
      echo "::error::Deep audit failed: $(jq -r '.error // "unknown error"' "$tmp")"
      exit 1 ;;
    *) echo "Deep audit $status $(jq -r '[.progress // empty, .stage // empty] | map(tostring) | join(" ")' "$tmp")" ;;
  esac
done

score=$(jq -r '.result.scores.lai_score // empty' "$tmp")
grade=$(jq -r '.result.scores.lai_grade // empty' "$tmp")
high=$(jq '[.result.findings[]? | select(.severity == "high" or .severity == "critical")] | length' "$tmp")
total=$(jq '[.result.findings[]?] | length' "$tmp")
# Quota left after this run (best effort; never fails the step). The main host
# serves it at /deep-audit/usage; the legacy engine host at /usage.
case "${BASE#*://}" in engine.*) usage_path=/usage ;; *) usage_path=/deep-audit/usage ;; esac
remaining=""
ucode=$(curl -sS -o "$hdr" -w '%{http_code}' "$BASE$usage_path" \
  -H "X-API-Key: $SSA_API_KEY" -H "User-Agent: seo-audit-action/1.1.0") || ucode=000
if [ "$ucode" = "200" ]; then
  remaining=$(jq -r '.site_audit.remaining // empty' "$hdr" 2>/dev/null || true)
fi
{
  echo "deep-audit-remaining=$remaining"
  echo "deep-audit-score=$score"
  echo "deep-audit-grade=$grade"
  echo "deep-audit-high-findings=$high"
} >> "$OUT"

{
  echo "## Deep Site Audit"
  echo ""
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| URL | $SSA_URL |"
  echo "| Score | **$score** ($grade) |"
  echo "| High/critical findings | $high of $total |"
  [ -n "$remaining" ] && echo "| Deep Audits left this month | $remaining |"
  echo ""
  if [ "$total" -gt 0 ]; then
    echo "### Top findings"
    jq -r '.result.findings | sort_by(if .severity == "critical" then 0 elif .severity == "high" then 1 elif .severity == "medium" then 2 else 3 end) | .[:10][] | "- **[\(.severity)]** \(.evidence // .task_id)"' "$tmp"
  fi
} >> "$SUMMARY"

echo "Deep audit score: $score ($grade), $high high/critical findings"

if [ "${SSA_FAIL_ON_HIGH:-false}" = "true" ] && [ "$high" -gt 0 ]; then
  echo "::error::Deep audit found $high high/critical findings"
  exit 1
fi
