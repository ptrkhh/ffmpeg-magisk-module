#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/lib.sh

fail() { echo "FAIL: $1" >&2; exit 1; }

# valid lock
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/ok.lock" <<EOF
UPSTREAM_REPO=yearsyan/ffmpeg-android-build
UPSTREAM_TAG=v7.1-beta.16
ASSET=ffmpeg_android_aarch64_gpl.tar.gz
ASSET_SHA512=abc123
EOF
LOCK_FILE="$tmp/ok.lock"
[ "$(lock_get UPSTREAM_REPO)" = "yearsyan/ffmpeg-android-build" ] || fail "repo"
[ "$(lock_get UPSTREAM_TAG)"  = "v7.1-beta.16" ] || fail "tag"

# malicious value must abort (command substitution attempt)
cat > "$tmp/bad.lock" <<'EOF'
ASSET=$(rm -rf /)
EOF
LOCK_FILE="$tmp/bad.lock"
if (lock_get ASSET) 2>/dev/null; then fail "accepted malicious value"; fi

# missing key must abort
LOCK_FILE="$tmp/ok.lock"
if (lock_get NOPE) 2>/dev/null; then fail "accepted missing key"; fi

echo "PASS test_lib_lock"
