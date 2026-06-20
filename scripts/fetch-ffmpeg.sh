#!/bin/sh
# Host-only (CI ubuntu / maintainer). POSIX sh. Downloads the pinned upstream asset,
# verifies SHA512 fail-closed, extracts ffmpeg+ffprobe into system/bin.
# NEVER `curl | tar`: verify-before-extract (spec §6 step 0).
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
. "$root/scripts/lib.sh"

REPO=$(lock_get UPSTREAM_REPO)
TAG=$(lock_get UPSTREAM_TAG)
ASSET=$(lock_get ASSET)
ASSET_SHA512=$(lock_get ASSET_SHA512)
FFMPEG_SHA512=$(lock_get FFMPEG_SHA512)
FFPROBE_SHA512=$(lock_get FFPROBE_SHA512)

[ "$REPO" = "$UPSTREAM_REPO_ALLOWED" ] || { echo "upstream repo not allowlisted: $REPO" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
base=${FETCH_URL_BASE:-"https://github.com/$REPO/releases/download/$TAG"}
url="$base/$ASSET"
echo "fetch: $url"
curl -fL --proto '=https' --tlsv1.2 -o "$tmp/asset.tgz" "$url" 2>/dev/null \
  || curl -fL -o "$tmp/asset.tgz" "$url"   # file:// for tests has no https proto

echo "verify: asset sha512"
printf '%s  %s\n' "$ASSET_SHA512" "$tmp/asset.tgz" | sha512sum -c - >/dev/null 2>&1 \
  || { echo "ASSET_SHA512 MISMATCH — STOP (spec §13). system/bin untouched." >&2; exit 1; }

memf=$(tar -tzf "$tmp/asset.tgz" | grep -E '(^|/)bin/ffmpeg$'  | head -n1 || true)
memp=$(tar -tzf "$tmp/asset.tgz" | grep -E '(^|/)bin/ffprobe$' | head -n1 || true)
[ -n "$memf" ] && [ -n "$memp" ] \
  || { echo "expected bin/ffmpeg|bin/ffprobe not present in archive" >&2; exit 1; }

mkdir -p "$tmp/x"
tar -xzf "$tmp/asset.tgz" -C "$tmp/x" "$memf" "$memp"

echo "verify: per-binary sha512"
printf '%s  %s\n' "$FFMPEG_SHA512"  "$tmp/x/$memf" | sha512sum -c - >/dev/null 2>&1 || { echo "ffmpeg sha512 mismatch" >&2; exit 1; }
printf '%s  %s\n' "$FFPROBE_SHA512" "$tmp/x/$memp" | sha512sum -c - >/dev/null 2>&1 || { echo "ffprobe sha512 mismatch" >&2; exit 1; }

mkdir -p system/bin
mv -f "$tmp/x/$memf" system/bin/ffmpeg
mv -f "$tmp/x/$memp" system/bin/ffprobe
chmod 0755 system/bin/ffmpeg system/bin/ffprobe
echo "ok: system/bin/{ffmpeg,ffprobe} installed"
