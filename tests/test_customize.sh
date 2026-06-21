#!/bin/sh
# Drives customize.sh with stubbed Magisk functions/vars.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# --- arm64: expect two set_perm calls, no abort ---
log="$tmp/perm.log"; : > "$log"
ARCH=arm64 MODPATH=/m sh -c '
  ui_print(){ :; }; abort(){ echo "ABORT:$*"; exit 9; }
  set_perm(){ echo "$@" >> "'"$log"'"; }
  . ./customize.sh
' || fail "arm64 path aborted unexpectedly"
[ "$(grep -c '/m/system/bin/ffmpeg 0 2000 0755'  "$log")" -eq 1 ] || fail "no ffmpeg set_perm"
[ "$(grep -c '/m/system/bin/ffprobe 0 2000 0755' "$log")" -eq 1 ] || fail "no ffprobe set_perm"

# --- non-arm64: expect abort (exit 9) ---
if ARCH=x86 MODPATH=/m sh -c '
  ui_print(){ :; }; abort(){ echo "ABORT:$*"; exit 9; }
  set_perm(){ :; }
  . ./customize.sh
' 2>/dev/null; then fail "x86 did not abort"; fi

echo "PASS test_customize"
