#!/bin/sh
# Host-only. Validate a built module ZIP. Usage: selftest-zip.sh <zip>
set -eu
zip=${1:?usage: selftest-zip.sh <zip>}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
unzip -q "$zip" -d "$tmp"

found=$(find "$tmp/system/bin" -maxdepth 1 -type f ! -name '.gitkeep' -printf '%f\n' 2>/dev/null | sort | tr '\n' ' ')
[ "$found" = "ffmpeg ffprobe " ] || { echo "system/bin != {ffmpeg,ffprobe}: [$found]" >&2; exit 1; }

for b in ffmpeg ffprobe; do
  f="$tmp/system/bin/$b"
  file "$f" | grep -q 'ELF 64-bit LSB.*ARM aarch64' || { echo "$b not arm64 ELF" >&2; exit 1; }
  readelf -h "$f" | grep -q 'Class:[[:space:]]*ELF64'   || { echo "$b not ELF64" >&2; exit 1; }
  readelf -h "$f" | grep -q 'Machine:.*AArch64'         || { echo "$b not AArch64" >&2; exit 1; }
  [ -x "$f" ] || { echo "$b not executable" >&2; exit 1; }
  # if/fi + `|| true`: under sh/ash, set -e aborts on `bad=$(...while...)` when the
  # loop's last test is false (a bare `[ ] && echo` exits non-zero).
  bad=$(readelf -lW "$f" | awk '/LOAD/{print $NF}' | while read -r a; do
          if [ "$((a))" -lt 16384 ]; then echo bad; fi; done) || true
  [ -z "$bad" ] || { echo "$b LOAD align < 16KB" >&2; exit 1; }
done
echo "selftest ok: $zip"
