#!/bin/sh
# Verifies fetch aborts and leaves system/bin untouched when ASSET_SHA512 is wrong.
# Uses a local file:// asset so the test needs no network.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# build a fake upstream tarball with bin/ffmpeg + bin/ffprobe
mkdir -p "$tmp/up/bin"; echo dummy-ffmpeg > "$tmp/up/bin/ffmpeg"; echo dummy-ffprobe > "$tmp/up/bin/ffprobe"
( cd "$tmp/up" && tar -czf "$tmp/asset.tgz" bin )

# lock with a DELIBERATELY WRONG asset sha512
cat > "$tmp/ffmpeg.lock" <<EOF
UPSTREAM_REPO=yearsyan/ffmpeg-android-build
UPSTREAM_TAG=local
ASSET=asset.tgz
ASSET_SHA512=0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
FFMPEG_SHA512=x
FFPROBE_SHA512=x
EOF

# sentinel in system/bin must survive
guard="system/bin/.fetch_test_guard"; : > "$guard"
# Point the downloader at our local file by overriding FETCH_URL_BASE.
if LOCK_FILE="$tmp/ffmpeg.lock" FETCH_URL_BASE="file://$tmp" \
   sh scripts/fetch-ffmpeg.sh 2>/dev/null; then
  rm -f "$guard"; fail "fetch succeeded on bad checksum"
fi
[ -f "$guard" ] || fail "system/bin was disturbed on failure"
[ ! -f system/bin/ffmpeg ] || { rm -f "$guard"; fail "ffmpeg written despite bad checksum"; }
rm -f "$guard"
echo "PASS test_fetch_failclosed"
