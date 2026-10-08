#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTROL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY="$CONTROL_ROOT/programs/qa-fixture-write-policy.sh"
PASS=0
FAIL=0
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

assert_policy() {
  local description="$1"
  local expected="$2"
  shift 2
  local output=""

  if output="$(bash "$POLICY" "$@" 2>/dev/null)" \
    && [ "$output" = "$expected" ]; then
    pass
  else
    fail "$description"
  fi
}

assert_policy \
  'R03 canonical prepare must require remote cleanup and reseed protection' \
  'QA_FIXTURE_WRITE_POLICY remote=1 reseed=1' \
  --scene R03 --case CS-02 --operation prepare --seed r02_end

assert_policy \
  'R13 canonical prepare must require remote cleanup and reseed protection' \
  'QA_FIXTURE_WRITE_POLICY remote=1 reseed=1' \
  --scene R13 --case RC-06 --operation prepare --seed r09_stale_schedule

assert_policy \
  'R06 large history overlay must remain local-only' \
  'QA_FIXTURE_WRITE_POLICY remote=0 reseed=0' \
  --scene R06 --case HD-07 --operation prepare --seed r06_large_history

assert_policy \
  'R06 large history cleanup must remain local-only' \
  'QA_FIXTURE_WRITE_POLICY remote=0 reseed=0' \
  --scene R06 --case HD-07 --operation prepare --seed r06_large_history_cleanup

if bash "$POLICY" \
  --scene R03 --case CS-02 --operation prepare --seed r09_stale_schedule \
  > "$TEST_ROOT/policy.out" \
  2> "$TEST_ROOT/policy.err"; then
  fail 'mismatched scene and seed must fail closed'
elif [ ! -s "$TEST_ROOT/policy.out" ] \
  && grep -Fxq QA_FIXTURE_WRITE_POLICY_REJECTED \
    "$TEST_ROOT/policy.err"; then
  pass
else
  fail 'rejection must use a fixed safe code'
fi

printf '=== Results: %s passed, %s failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
