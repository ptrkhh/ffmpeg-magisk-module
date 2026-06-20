#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
[ "$(sh scripts/versioncode.sh 20260620 0)" = "202606200" ] || fail "base"
[ "$(sh scripts/versioncode.sh 20260620 1)" = "202606201" ] || fail "same-day r1"
[ "$(sh scripts/versioncode.sh 99991231 9)" = "999912319" ] || fail "max bound"
if sh scripts/versioncode.sh 20260620 10 2>/dev/null; then fail "R=10 accepted"; fi
if sh scripts/versioncode.sh 2026062 0 2>/dev/null; then fail "bad date accepted"; fi
echo "PASS test_versioncode"
