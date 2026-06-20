#!/bin/sh
# Host-only. Bumps ffmpeg.lock to <new-tag>: owner-assert, TOFU confirm, download,
# 16KB-alignment assert (MGK-7), compute SHA512s, rewrite lock.
# Usage: scripts/update-pin.sh <new-tag> [--yes]
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd); cd "$root"
. "$root/scripts/lib.sh"

newtag=${1:-}; [ -n "$newtag" ] || { echo "usage: update-pin.sh <new-tag> [--yes]" >&2; exit 2; }
yes=0; [ "${2:-}" = "--yes" ] && yes=1
REPO="$UPSTREAM_REPO_ALLOWED"
ASSET="ffmpeg_android_aarch64_gpl.tar.gz"

# (a) provenance sanity (SEC-2): the source ORG is fixed by the hardcoded allowlist
# (REPO=$UPSTREAM_REPO_ALLOWED), so we do NOT assert release author identity — yearsyan
# publishes via github-actions[bot], and an author check would be both brittle and weak.
# Instead assert the release/tag actually exists in that repo AND publishes the expected
# asset (catches deleted tags / pulled assets — a real STOP condition).
api=$(curl -fsSL --proto '=https' --tlsv1.2 "https://api.github.com/repos/$REPO/releases/tags/$newtag") \
  || { echo "release tag '$newtag' not found in $REPO — abort" >&2; exit 1; }
printf '%s' "$api" | grep -qF "\"$ASSET\"" \
  || { echo "asset '$ASSET' not present in $REPO release '$newtag' — abort" >&2; exit 1; }

# (b) TOFU confirm
if [ "$yes" -ne 1 ]; then
  echo "WARNING: upstream publishes no signature/checksum; this pin trusts bytes served now."
  echo "Audit https://github.com/$REPO/releases/tag/$newtag before continuing."
  printf "Proceed? [y/N] "; read -r ans
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
  # NOTE: under `sh`/ash, `set -e` aborts on `_bad=$(...)` when the pipeline's last
  # command (the while loop) exits non-zero — which a bare `[ ] && echo` does on a
  # false test. Use `if/fi` (always exit 0) AND `|| true` to stay portable.
  _bad=$(readelf -lW "$1" | awk '/LOAD/{print $NF}' | while read -r a; do
           if [ "$((a))" -lt 16384 ]; then echo bad; fi
         done) || true
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
# GPLv2 §3 (SEC-6): archive the upstream build tree at the pinned tag, so a later
# upstream deletion cannot strand corresponding-source. Gitignored locally; CI also
# rebuilds + attaches it to the Release.
src_tarball="corresponding-source-$newtag.tar.gz"
curl -fL --proto '=https' --tlsv1.2 -o "$tmp/src.tar.gz" \
  "https://github.com/$REPO/archive/refs/tags/$newtag.tar.gz"
cp "$tmp/src.tar.gz" "$src_tarball"

echo "ffmpeg.lock updated -> $newtag (ffmpeg $ver)"
echo "wrote $src_tarball (GPLv2 §3 corresponding source)"
