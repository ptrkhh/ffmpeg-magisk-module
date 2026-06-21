#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/system/bin"
printf '#!/bin/sh\necho "ffmpeg version nTEST"\n'  > "$tmp/system/bin/ffmpeg"
printf '#!/bin/sh\necho "ffprobe version nTEST"\n' > "$tmp/system/bin/ffprobe"
chmod +x "$tmp/system/bin/ffmpeg" "$tmp/system/bin/ffprobe"
cp action.sh "$tmp/action.sh"
# Magisk invokes action.sh by path, so $0 contains a slash -> MODDIR=${0%/*} resolves.
# Invoke as ./action.sh to mirror that (bare `sh action.sh` would leave $0 slash-less).
out=$(cd "$tmp" && sh ./action.sh)
echo "$out" | grep -q 'ffmpeg version nTEST'  || fail "ffmpeg line missing"
echo "$out" | grep -q 'ffprobe version nTEST' || fail "ffprobe line missing"
echo "PASS test_action"
