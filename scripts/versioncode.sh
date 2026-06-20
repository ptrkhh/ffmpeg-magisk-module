#!/bin/sh
# Host-only. Prints versionCode = YYYYMMDD*10 + R. Usage: versioncode.sh <YYYYMMDD> <R(0..9)>
set -eu
d=${1:-}; r=${2:-}
case "$d" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) echo "bad date (want YYYYMMDD): $d" >&2; exit 1;; esac
case "$r" in [0-9]) ;; *) echo "R must be a single digit 0..9: $r" >&2; exit 1;; esac
echo $(( d * 10 + r ))
