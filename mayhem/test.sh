#!/usr/bin/env bash
#
# mayhem/test.sh — RUN pen's upstream unit test suite (pre-built by mayhem/build.sh).
#
# Upstream's suite (tools/unit_test.sh) is `cargo test` run in every directory that
# holds a Cargo.lock: the root workspace (all compiler crates: parse, ast, hir, mir,
# format, app, ...) plus cmd/test and each packages/*/ffi crate. We run exactly that
# (minus the additive mayhem/fuzz harness crate, which contains no tests) and
# aggregate cargo's per-suite "test result:" lines into one CTRF summary.
#
# The cucumber feature suite (features/, tools/integration_test.sh) is NOT run here:
# it needs Ruby/bundler, four rustup cross targets (musl + wasm32-wasip2), valgrind
# and a network `cargo install turtle-build` — not runnable in the air-gapped image.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

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

PASSED=0 FAILED=0 SKIPPED=0
log="$(mktemp)"
for d in $(git ls-files 'Cargo.lock' '**/Cargo.lock' | grep -v '^mayhem/'); do
  dir="$(dirname "$d")"
  echo "=== cargo test in $dir ==="
  ( cd "$dir" && env -u RUSTFLAGS cargo test ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  # cargo prints one line per suite: "test result: ok. N passed; N failed; N ignored; ..."
  while read -r p f i; do
    PASSED=$((PASSED + p)); FAILED=$((FAILED + f)); SKIPPED=$((SKIPPED + i))
  done < <(grep -E '^test result:' "$log" | sed -E 's/^test result: [^.]+\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored.*/\1 \2 \3/')
  # A compile error or crashed runner produces no "test result:" line — count the dir as a failure.
  if [ "$rc" -ne 0 ] && ! grep -qE '^test result:.* [1-9][0-9]* failed' "$log"; then
    echo "ERROR: cargo test in $dir exited $rc without reporting failures" >&2
    FAILED=$((FAILED + 1))
  fi
done
rm -f "$log"

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$SKIPPED"
