#!/usr/bin/env bash
#
# mayhem/test.sh — RUN image-png's OWN upstream test suite (already compiled by
# mayhem/build.sh via `cargo test --no-run`). This is the ENTIRE upstream cargo
# suite: src unit tests (adam7, decoder, encoder, filter, text_metadata, ...) plus
# the integration tests (tests/bugfixes.rs, tests/check_testimages.rs — golden CRC
# known-answer checks over the PngSuite corpus — and tests/partial_decode.rs) and
# doc-tests. It asserts decoded output against reference CRCs/values, so a
# neutered/no-op library fails it.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# RUN the upstream cargo test suite. build.sh already compiled it with the same
# (normal, non-fuzzing) flags, so this only runs the pre-built binaries.
export PATH="/opt/toolchains/rust/cargo/bin:$PATH"
unset RUSTFLAGS

LOG="/tmp/cargo-test.log"
env -u RUSTFLAGS cargo test -p png 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

# Sum every per-suite summary line: "test result: ok. X passed; Y failed; Z ignored; ..."
read -r PASSED FAILED SKIPPED <<<"$(awk '
  /^test result:/ {
    for (i=1;i<=NF;i++) {
      if ($(i+1) ~ /^passed/)  p += $i;
      if ($(i+1) ~ /^failed/)  f += $i;
      if ($(i+1) ~ /^ignored/) s += $i;
    }
  }
  END { printf "%d %d %d", p+0, f+0, s+0 }' "$LOG")"

# Honesty guards: a cargo that dies (or is neutered) parses as 0 tests — that is a
# failure, and a non-zero cargo exit with 0 parsed failures is forced to a failure too.
if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then FAILED=1; fi
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=1; fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$SKIPPED"
