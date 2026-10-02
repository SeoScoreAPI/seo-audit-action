#!/usr/bin/env bash
# Offline tests for scripts/deep-audit.sh: a stub `curl` replays canned responses
# and logs every request. Run: bash test/test-deep-audit.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/scripts/deep-audit.sh"
fails=0

setup() {
  T=$(mktemp -d)
  mkdir -p "$T/bin" "$T/resp"
  cat > "$T/bin/curl" <<'STUB'
#!/usr/bin/env bash
# Replays $STUB_DIR/resp/N.{code,body,headers} in order; logs "METHOD URL BODY".
out=/dev/null hdr=""; method=GET; data=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -D) hdr="$2"; shift ;;
    -w|-H) shift ;;
    -X) method="$2"; shift ;;
    -d) data="$2"; shift ;;
    -sS) ;;
    *) url="$1" ;;
  esac
  shift
done
n=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$STUB_DIR/n"
echo "$method $url $data" >> "$STUB_DIR/log"
cp "$STUB_DIR/resp/$n.body" "$out"
[ -n "$hdr" ] && { cat "$STUB_DIR/resp/$n.headers" 2>/dev/null || true; } > "$hdr"
cat "$STUB_DIR/resp/$n.code"
STUB
  chmod +x "$T/bin/curl"
  i=0
}

respond() {  # code body [headers]
  i=$((i + 1))
  echo -n "$1" > "$T/resp/$i.code"
  echo "$2" > "$T/resp/$i.body"
  [ $# -gt 2 ] && printf '%s\r\n' "$3" > "$T/resp/$i.headers"
}

run() {
  env PATH="$T/bin:$PATH" STUB_DIR="$T" GITHUB_OUTPUT="$T/out" GITHUB_STEP_SUMMARY="$T/summary" \
    SSA_URL="https://example.com" SSA_API_KEY="k" SSA_POLL_INTERVAL=0 "$@" bash "$SCRIPT" > "$T/stdout" 2>&1
}

check() {  # name condition...
  local name="$1"; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); sed 's/^/     /' "$T/stdout" "$T/log" 2>/dev/null; fi
}

DONE='{"status":"completed","result":{"scores":{"lai_score":3.23,"lai_grade":"fair"},"findings":[{"task_id":"2.2.01","severity":"high","evidence":"No XML sitemap found"},{"task_id":"1.1","severity":"low","evidence":"minor"}]}}'

# 1. Happy path on the main host
setup
respond 200 '{"job_id":"abc","status":"queued"}'
respond 200 '{"status":"queued","queue_position":1}'
respond 200 '{"status":"running","progress":50,"stage":"Section 4"}'
respond 200 "$DONE"
run SSA_BUSINESS_TYPE=saas; rc=$?
check "completes with exit 0" test "$rc" = 0
check "starts on the main host" grep -q '^POST https://seoscoreapi.com/site-audit {"url":"https://example.com","business_type":"saas"}$' "$T/log"
check "polls the job on the main host" grep -q '^GET https://seoscoreapi.com/site-audit/abc' "$T/log"
check "writes score output" grep -qx 'deep-audit-score=3.23' "$T/out"
check "writes job id output" grep -qx 'deep-audit-job-id=abc' "$T/out"
check "counts high findings" grep -qx 'deep-audit-high-findings=1' "$T/out"
check "summary lists findings" grep -q 'No XML sitemap found' "$T/summary"

# 2. Base URL override + 429 backpressure
setup
respond 429 '{"detail":"queue full"}' 'Retry-After: 0'
respond 200 '{"job_id":"xyz","status":"queued"}'
respond 200 "$DONE"
run SSA_BASE_URL="https://engine.seoscoreapi.com/"; rc=$?
check "retries after 429" test "$(grep -c '^POST' "$T/log")" = 2
check "honours base URL override" grep -q '^GET https://engine.seoscoreapi.com/site-audit/xyz' "$T/log"
check "override run exits 0" test "$rc" = 0

# 3. Failed job
setup
respond 200 '{"job_id":"abc"}'
respond 200 '{"status":"failed","error":"boom"}'
run; rc=$?
check "failed job exits 1" test "$rc" = 1
check "failed job reports the error" grep -q 'boom' "$T/stdout"

# 4. Start refused (no credits)
setup
respond 402 '{"detail":"No Deep Audit credits left"}'
run; rc=$?
check "402 exits 1 with the detail" bash -c "[ $rc = 1 ] && grep -q 'No Deep Audit credits left' '$T/stdout'"

# 5. fail-on-high
setup
respond 200 '{"job_id":"abc"}'
respond 200 "$DONE"
run SSA_FAIL_ON_HIGH=true; rc=$?
check "fail-on-high exits 1 when high findings" test "$rc" = 1

# 6. Timeout
setup
respond 200 '{"job_id":"abc"}'
run SSA_TIMEOUT=-1; rc=$?
check "timeout exits 1" bash -c "[ $rc = 1 ] && grep -q 'did not finish' '$T/stdout'"

echo
if [ "$fails" -eq 0 ]; then echo "all tests passed"; else echo "$fails failed"; exit 1; fi
