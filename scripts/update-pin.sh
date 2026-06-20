#!/bin/sh
# Host-only. Bumps ffmpeg.lock to <new-tag>: owner-assert, TOFU confirm, download,
# 16KB-alignment assert (MGK-7), compute SHA512s, rewrite lock.
# Usage: scripts/update-pin.sh <new-tag> [--yes]
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd); cd "$root"
. "$root/scripts/lib.sh"

newtag=${1:-}; [ -n "$newtag" ] || { echo "usage: update-pin.sh <new-tag> [--yes]" >&2; exit 2; }
yes=0; [ "${2:-}" = "--yes" ] && yes=1
REPO="$UPSTREAM_REPO_ALLOWED"
ASSET="ffmpeg_android_aarch64_gpl.tar.gz"

# (a) owner assertion (SEC-2)
owner=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$newtag" \
        | grep -E '"login"' | head -n1 | sed -E 's/.*"login": *"([^"]+)".*/\1/')
[ "$owner" = "yearsyan" ] || { echo "release owner/login != yearsyan (got '$owner') — abort" >&2; exit 1; }

# (b) TOFU confirm
if [ "$yes" -ne 1 ]; then
  echo "WARNING: upstream publishes no signature/checksum; this pin trusts bytes served now."
  echo "Audit https://github.com/$REPO/releases/tag/$newtag before continuing."
  printf "Proceed? [y/N] "; read ans
  [ "$ans" = y ] || [ "$ans" = Y ] || { echo aborted; exit 1; }
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fL --proto '=https' --tlsv1.2 -o "$tmp/asset.tgz" \
  "https://github.com/$REPO/releases/download/$newtag/$ASSET"
asset_sha=$(sha512sum "$tmp/asset.tgz" | cut -d' ' -f1)

memf=$(tar -tzf "$tmp/asset.tgz" | grep -E '(^|/)bin/ffmpeg$'  | head -n1)
memp=$(tar -tzf "$tmp/asset.tgz" | grep -E '(^|/)bin/ffprobe$' | head -n1)
[ -n "$memf" ] && [ -n "$memp" ] || { echo "archive missing bin/ffmpeg|bin/ffprobe" >&2; exit 1; }
mkdir -p "$tmp/x"; tar -xzf "$tmp/asset.tgz" -C "$tmp/x" "$memf" "$memp"
ff_sha=$(sha512sum "$tmp/x/$memf" | cut -d' ' -f1)
fp_sha=$(sha512sum "$tmp/x/$memp" | cut -d' ' -f1)

# 16KB-alignment assert (MGK-7): every PT_LOAD Align must be >= 0x4000 (16384)
assert16k() {
  _bad=$(readelf -lW "$1" | awk '/LOAD/{print $NF}' | while read -r a; do
           [ "$((a))" -lt 16384 ] && echo bad; done)
  [ -z "$_bad" ] || { echo "16KB alignment regression in $1" >&2; exit 1; }
}
assert16k "$tmp/x/$memf"; assert16k "$tmp/x/$memp"

# derive ffmpeg version from the binary (works on arm64 host; fallback keeps current)
chmod +x "$tmp/x/$memf" 2>/dev/null || true
ver=$("$tmp/x/$memf" -version 2>/dev/null | head -n1 | sed -E 's/^ffmpeg version n?([0-9.]+).*/\1/' || true)
[ -n "${ver:-}" ] || ver=$(lock_get FFMPEG_VERSION 2>/dev/null || echo "unknown")

cat > ffmpeg.lock <<EOF
UPSTREAM_REPO=$REPO
UPSTREAM_TAG=$newtag
FFMPEG_VERSION=$ver
ASSET=$ASSET
ASSET_SHA512=$asset_sha
FFMPEG_SHA512=$ff_sha
FFPROBE_SHA512=$fp_sha
EOF
echo "ffmpeg.lock updated -> $newtag (ffmpeg $ver)"
echo "REMINDER: archive corresponding source (GPLv2 §3) — Task 17 / spec §15."
