#!/bin/sh
# Happy path: CORRECT checksums -> fetch installs both binaries (mode 0755).
# Uses a local file:// asset (no network). Guards the verify-then-install path
# that the fail-closed test alone does not exercise (regression: a parser that
# rejects SHA512 keys would make fail-closed pass for the wrong reason).
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

tmp=$(mktemp -d); bak=$(mktemp -d)
# Preserve any REAL installed binaries so this test never clobbers them (it installs
# dummies into system/bin). Restore them on exit instead of deleting.
for b in ffmpeg ffprobe; do if [ -e "system/bin/$b" ]; then mv "system/bin/$b" "$bak/$b"; fi; done
restore() {
  rm -f system/bin/ffmpeg system/bin/ffprobe
  for b in ffmpeg ffprobe; do if [ -e "$bak/$b" ]; then mv "$bak/$b" "system/bin/$b"; fi; done
  rm -rf "$tmp" "$bak"
}
trap restore EXIT
mkdir -p "$tmp/up/bin"
echo real-ffmpeg  > "$tmp/up/bin/ffmpeg"
echo real-ffprobe > "$tmp/up/bin/ffprobe"
( cd "$tmp/up" && tar -czf "$tmp/asset.tgz" bin )

asha=$(sha512sum "$tmp/asset.tgz" | cut -d' ' -f1)
mkdir -p "$tmp/x"; tar -xzf "$tmp/asset.tgz" -C "$tmp/x" bin/ffmpeg bin/ffprobe
fsha=$(sha512sum "$tmp/x/bin/ffmpeg"  | cut -d' ' -f1)
psha=$(sha512sum "$tmp/x/bin/ffprobe" | cut -d' ' -f1)

cat > "$tmp/ffmpeg.lock" <<EOF
UPSTREAM_REPO=yearsyan/ffmpeg-android-build
UPSTREAM_TAG=local
ASSET=asset.tgz
ASSET_SHA512=$asha
FFMPEG_SHA512=$fsha
FFPROBE_SHA512=$psha
EOF

LOCK_FILE="$tmp/ffmpeg.lock" FETCH_URL_BASE="file://$tmp" sh scripts/fetch-ffmpeg.sh >/dev/null
[ "$(cat system/bin/ffmpeg)"  = real-ffmpeg  ] || fail "ffmpeg not installed/correct"
[ "$(cat system/bin/ffprobe)" = real-ffprobe ] || fail "ffprobe not installed/correct"
[ -x system/bin/ffmpeg ] && [ -x system/bin/ffprobe ] || fail "missing exec bit"
echo "PASS test_fetch_happy"
