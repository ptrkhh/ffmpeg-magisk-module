#!/bin/sh
# Host-only shared helpers (POSIX sh; NOT run on-device).
# ffmpeg.lock is DATA, not code — parsed here by strict regex, never sourced (SEC-8).

UPSTREAM_REPO_ALLOWED="yearsyan/ffmpeg-android-build"
: "${LOCK_FILE:=ffmpeg.lock}"

# lock_get KEY -> prints value; aborts on missing/duplicate/malformed line.
lock_get() {
  _k=$1
  _line=$(grep -E "^${_k}=" "$LOCK_FILE" 2>/dev/null || true)
  [ -n "$_line" ] || { echo "lock: missing key $_k" >&2; return 1; }
  [ "$(printf '%s\n' "$_line" | grep -c .)" -eq 1 ] || { echo "lock: duplicate key $_k" >&2; return 1; }
  printf '%s' "$_line" | grep -Eq '^[A-Z_]+=[A-Za-z0-9._/:+-]+$' \
    || { echo "lock: malformed line for $_k" >&2; return 1; }
  printf '%s' "${_line#*=}"
}
