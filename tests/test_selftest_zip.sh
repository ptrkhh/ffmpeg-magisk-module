#!/bin/sh
# Requires Task 6 to have populated system/bin/{ffmpeg,ffprobe}.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f system/bin/ffmpeg ] && [ -f system/bin/ffprobe ] || fail "run Task 6 first (binaries absent)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# good zip (excludes .gitkeep, like the real package step)
zip -q -r9 "$tmp/good.zip" META-INF system module.prop customize.sh COPYING -x 'system/bin/.gitkeep'
sh scripts/selftest-zip.sh "$tmp/good.zip" || fail "good zip rejected"

# bad zip: drop ffprobe -> must fail
mkdir -p "$tmp/bad/system/bin"; cp system/bin/ffmpeg "$tmp/bad/system/bin/ffmpeg"
( cd "$tmp/bad" && zip -q -r9 "$tmp/bad.zip" system )
if sh scripts/selftest-zip.sh "$tmp/bad.zip" 2>/dev/null; then fail "bad zip (missing ffprobe) accepted"; fi

echo "PASS test_selftest_zip"
