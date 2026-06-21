# FFmpeg Binary Supply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the manual ffmpeg Magisk skeleton into a module whose arm64 `ffmpeg`+`ffprobe` are supplied automatically from a pinned, SHA512-verified upstream prebuilt, packaged into a flashable ZIP by CI and published as a GitHub Release.

**Architecture:** A small set of host-only POSIX-`sh` build scripts (`scripts/`) read a committed, regex-parsed pin file (`ffmpeg.lock`), download + verify + extract the binaries into `system/bin/` (gitignored). A tag-triggered GitHub Actions workflow runs the same scripts, self-tests the ZIP, publishes a Release, and refreshes the in-app `updateJson` feed. The flashed module itself is just `customize.sh` (arch guard + perms) + `action.sh` (version button) + the two binaries.

**Tech Stack:** POSIX `sh` (BusyBox `ash` on-device; bash/ash on host), GitHub Actions, Magisk module format (v20.4+ install floor; v28.0+ for the Action button), `curl`/`tar`/`sha512sum`/`readelf`/`file`/`unzip`, `shellcheck`/`actionlint` as lint gates.

**Tags:** `[E]` = essential (lean module works without the rest). `[P]` = polish (defer-able hardening). Implement all `[E]` first; `[P]` tasks are independent and can be skipped or done later.

**Spec:** `docs/superpowers/specs/2026-06-20-ffmpeg-binary-supply-design.md` — section refs (§N, SEC-/MGK-/CI-/CONS-) below point into it.

---

## File Structure

Created/modified, by responsibility:

| Path | Responsibility | Task |
|---|---|---|
| `.gitattributes` | LF for text/scripts, `binary` for `system/**` (CI-8) | 1 |
| `.gitignore` | ignore both binaries, keep `.gitkeep` (CONS-1/2) | 2 |
| `system/bin/.gitkeep` | tracked placeholder so dir survives clean checkout | 2 |
| `scripts/lib.sh` | safe regex `lock_get` parser (SEC-8), shared constant allowlist | 3 |
| `scripts/fetch-ffmpeg.sh` | download → verify → extract → install (SEC-1/3) | 4 |
| `scripts/update-pin.sh` | bump pin: fetch tag, owner/TOFU/16KB checks, rewrite lock (SEC-2, MGK-7) | 5 |
| `ffmpeg.lock` | committed pin: repo/tag/asset + SHA512s (CONS-5, §5) | 6 |
| `system/bin/{ffmpeg,ffprobe}` | the binaries (gitignored; produced by fetch) | 6 |
| `module.prop` | module metadata + `updateJson` + versionCode seed (§8) | 7 |
| `customize.sh` | arch guard + `set_perm` both binaries (MGK-3/4) | 8 |
| `COPYING` | GPLv2 text (§15) | 9 |
| `action.sh` | Magisk Action button: print versions (MGK-1/2) | 10 |
| `scripts/versioncode.sh` | pure `YYYYMMDD*10+R` arithmetic (CI-1/2) | 11 |
| `scripts/selftest-zip.sh` | validate a built ZIP: 2 arm64 ELFs, exec, 16KB (CI-6, MGK-7) | 12 |
| `update.json`, `changelog.txt` | Magisk updateJson feed + in-app changelog (§9, CONS-6) | 13 |
| `.github/workflows/release.yml` | tag→fetch→stamp→selftest→release→commit-back (§12) | 14 |
| `README.md` | rewrite; no manual-flow refs (CONS-9) | 15 |
| `CHANGELOG.md` | human cumulative repo changelog | 16 |
| `tests/*.sh` | plain-sh assertion harnesses (no extra deps) | 3,4,8,11,12 |

**Avoid (legacy template):** no `config.sh`, `common/*`, `system/xbin`, `minMagisk` (§4).

**Working branch:** `ffmpeg-auto-binary-supply` (already checked out). All commits land here.

---

## Task 1 [E]: `.gitattributes` — line-ending + binary control

**Files:**
- Create: `.gitattributes`

- [ ] **Step 1: Create `.gitattributes`**

```gitattributes
* text=auto eol=lf
META-INF/** text eol=lf
scripts/**  text eol=lf
*.sh        text eol=lf
module.prop text eol=lf
update.json text eol=lf
changelog.txt text eol=lf
ffmpeg.lock text eol=lf
*.json      text eol=lf
*.txt       text eol=lf
system/**   binary
```

- [ ] **Step 2: Verify attributes resolve**

Run:
```bash
git check-attr -a customize.sh module.prop ffmpeg.lock 2>/dev/null | grep -E 'eol: lf' | wc -l
git check-attr text system/bin/ffmpeg 2>/dev/null
```
Expected: first command prints `3` (or more); second prints `system/bin/ffmpeg: text: unset` (i.e. treated binary).

- [ ] **Step 3: Commit**

```bash
git add .gitattributes
git commit -m "build: add .gitattributes (LF for scripts/text, binary for system)"
```

---

## Task 2 [E]: `.gitignore` + tracked `system/bin/.gitkeep`

**Files:**
- Modify: `.gitignore` (replace the line `system/bin/ffmpeg`)
- Create: `system/bin/.gitkeep`

- [ ] **Step 1: Create the tracked placeholder**

```bash
mkdir -p system/bin
: > system/bin/.gitkeep
```

- [ ] **Step 2: Replace the binary-ignore line in `.gitignore`**

Find the existing final line `system/bin/ffmpeg` and replace it with:
```gitignore
system/bin/*
!system/bin/.gitkeep
```
(Leave all other `.gitignore` lines unchanged, including `.claude/`.)

- [ ] **Step 3: Verify both binaries are ignored and `.gitkeep` is tracked**

Run:
```bash
touch system/bin/ffmpeg system/bin/ffprobe
git check-ignore system/bin/ffmpeg system/bin/ffprobe   # both should print
git check-ignore system/bin/.gitkeep && echo IGNORED || echo TRACKED  # must print TRACKED
git status --porcelain system/bin/.gitkeep              # should show the new file staged-able
rm system/bin/ffmpeg system/bin/ffprobe
```
Expected: first prints both paths; second prints `TRACKED`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore system/bin/.gitkeep
git commit -m "build: ignore system/bin binaries, keep .gitkeep placeholder"
```

---

## Task 3 [E]: `scripts/lib.sh` — safe lock parser (TDD)

`ffmpeg.lock` is **data, not code** — parsed by strict regex, never `source`d (SEC-8).

**Files:**
- Create: `scripts/lib.sh`
- Test: `tests/test_lib_lock.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_lib_lock.sh`:
```sh
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
```

- [ ] **Step 2: Run it — must fail (lib.sh absent)**

Run: `sh tests/test_lib_lock.sh`
Expected: FAIL — `scripts/lib.sh: No such file or directory`.

- [ ] **Step 3: Implement `scripts/lib.sh`**

```sh
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
  printf '%s' "$_line" | grep -Eq '^[A-Z0-9_]+=[A-Za-z0-9._/:+-]+$' \
    || { echo "lock: malformed line for $_k" >&2; return 1; }
  printf '%s' "${_line#*=}"
}
```

- [ ] **Step 4: Run it — must pass**

Run: `sh tests/test_lib_lock.sh`
Expected: `PASS test_lib_lock`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh tests/test_lib_lock.sh
git commit -m "build: add scripts/lib.sh safe lock parser with tests"
```

---

## Task 4 [E]: `scripts/fetch-ffmpeg.sh` — download/verify/extract (TDD + shellcheck)

**Files:**
- Create: `scripts/fetch-ffmpeg.sh`
- Test: `tests/test_fetch_failclosed.sh`

- [ ] **Step 1: Write the failing test (fail-closed on hash mismatch, system/bin untouched)**

Create `tests/test_fetch_failclosed.sh`:
```sh
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
```

- [ ] **Step 2: Run it — must fail (script absent)**

Run: `sh tests/test_fetch_failclosed.sh`
Expected: FAIL — `scripts/fetch-ffmpeg.sh: No such file or directory`.

- [ ] **Step 3: Implement `scripts/fetch-ffmpeg.sh`**

```sh
#!/bin/sh
# Host-only (CI ubuntu / maintainer). POSIX sh. Downloads the pinned upstream asset,
# verifies SHA512 fail-closed, extracts ffmpeg+ffprobe into system/bin.
# NEVER `curl | tar`: verify-before-extract (spec §6 step 0).
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
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
```

- [ ] **Step 4: Run the test — must pass**

Run: `sh tests/test_fetch_failclosed.sh`
Expected: `PASS test_fetch_failclosed`.

- [ ] **Step 5: Lint (if shellcheck available)**

Run: `command -v shellcheck >/dev/null && shellcheck --shell=sh scripts/lib.sh scripts/fetch-ffmpeg.sh || echo "shellcheck not local; CI enforces"`
Expected: no warnings (or the skip note). Fix any real findings.

- [ ] **Step 6: Commit**

```bash
git add scripts/fetch-ffmpeg.sh tests/test_fetch_failclosed.sh
git commit -m "build: add fetch-ffmpeg.sh (verify-before-extract, fail-closed)"
```

---

## Task 5 [E]: `scripts/update-pin.sh` — bump the pin

Owner-assertion + TOFU confirm + 16KB assertion are inside this script. The interactive confirm/owner-check are `[P]`-flavored hardening but cheap; keep them, gated behind `--yes` for automation.

**Files:**
- Create: `scripts/update-pin.sh`

- [ ] **Step 1: Implement `scripts/update-pin.sh`**

```sh
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

# (a) provenance sanity (SEC-2): source ORG fixed by the hardcoded allowlist
# (REPO=$UPSTREAM_REPO_ALLOWED). Do NOT assert release author identity (yearsyan
# publishes via github-actions[bot] — brittle and weak). Assert the tag exists in the
# repo AND publishes the expected asset (catches deleted tags / pulled assets).
api=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$newtag") \
  || { echo "release tag '$newtag' not found in $REPO — abort" >&2; exit 1; }
printf '%s' "$api" | grep -qF "\"$ASSET\"" \
  || { echo "asset '$ASSET' not present in $REPO release '$newtag' — abort" >&2; exit 1; }

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
  # under sh/ash, `set -e` aborts on `_bad=$(...)` when the inner while loop exits
  # non-zero (a bare `[ ] && echo` does on a false test). Use if/fi + `|| true`.
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
echo "ffmpeg.lock updated -> $newtag (ffmpeg $ver)"
echo "REMINDER: archive corresponding source (GPLv2 §3) — Task 17 / spec §15."
```

- [ ] **Step 2: Lint**

Run: `command -v shellcheck >/dev/null && shellcheck --shell=sh scripts/update-pin.sh || echo "CI enforces"`
Expected: no warnings (the `read -r a` in the `awk|while` is intentional; if shellcheck flags SC2162 elsewhere, it is already `-r`).

- [ ] **Step 3: Commit**

```bash
git add scripts/update-pin.sh
git commit -m "build: add update-pin.sh (owner+TOFU+16KB checks, rewrites lock)"
```

---

## Task 6 [E]: Generate the real `ffmpeg.lock` and binaries (on-device integration)

This device is arm64 — run the real pin + fetch + on-device exec here.

**Files:**
- Create: `ffmpeg.lock` (generated; committed)
- Produce: `system/bin/{ffmpeg,ffprobe}` (gitignored; not committed)

- [ ] **Step 1: Generate the pin against the verified tag**

Run:
```bash
sh scripts/update-pin.sh v7.1-beta.16 --yes
cat ffmpeg.lock
```
Expected: `ffmpeg.lock` lists `UPSTREAM_TAG=v7.1-beta.16`, `FFMPEG_VERSION=7.1.1`, and three 128-hex-char SHA512 values. No 16KB-alignment error.

- [ ] **Step 2: Fetch + install the binaries from the new pin**

Run:
```bash
sh scripts/fetch-ffmpeg.sh
ls -l system/bin/ffmpeg system/bin/ffprobe
```
Expected: both files present, mode `0755`, ~28 MB each.

- [ ] **Step 3: On-device smoke test (arm64)**

Run:
```bash
./system/bin/ffmpeg  -version | head -n1
./system/bin/ffprobe -version | head -n1
./system/bin/ffmpeg -hide_banner -encoders | grep -E 'libx264|libx265' | head
```
Expected: ffmpeg/ffprobe report `n7.1.1`; `libx264` and `libx265` encoders listed.

- [ ] **Step 4: Confirm binaries are gitignored, lock is tracked**

Run:
```bash
git check-ignore system/bin/ffmpeg system/bin/ffprobe   # both print
git status --porcelain ffmpeg.lock                       # shows ?? or A
```
Expected: binaries ignored; `ffmpeg.lock` shows as a change to commit.

- [ ] **Step 5: Commit the lock only**

```bash
git add ffmpeg.lock
git commit -m "build: pin ffmpeg to yearsyan v7.1-beta.16 (n7.1.1 GPL arm64)"
```

---

## Task 7 [E]: `module.prop` rewrite

**Files:**
- Modify: `module.prop` (full rewrite)

- [ ] **Step 1: Replace `module.prop` contents**

```properties
id=ffmpeg_systemwide
name=FFmpeg for arm64-v8a devices
version=v7.1.1
versionCode=202606200
author=ptrkhh
description=Statically built GPL ffmpeg + ffprobe (libx264/libx265) system-wide for arm64-v8a. 16KB-page ready.
updateJson=https://raw.githubusercontent.com/ptrkhh/ffmpeg-magisk-module/main/update.json
```

- [ ] **Step 2: Verify fields**

Run:
```bash
grep -E '^(id|version|versionCode|updateJson)=' module.prop
awk -F= '/^versionCode=/{print ($2+0 < 2147483647) ? "INT32_OK" : "OVERFLOW"}' module.prop
```
Expected: four lines printed; `INT32_OK`.

- [ ] **Step 3: Commit**

```bash
git add module.prop
git commit -m "feat: module.prop metadata, versionCode scheme, updateJson"
```

---

## Task 8 [E]: `customize.sh` rewrite — arch guard + perms (TDD)

`$ARCH` is the Magisk literal (`arm`/`arm64`/`x86`/`x64`/`riscv64`) — compare to `arm64`, NOT `arm64-v8a` (MGK-3).

**Files:**
- Modify: `customize.sh` (full rewrite)
- Test: `tests/test_customize.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_customize.sh`:
```sh
#!/bin/sh
# Drives customize.sh with stubbed Magisk functions/vars.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# --- arm64: expect two set_perm calls, no abort ---
log="$tmp/perm.log"; : > "$log"
ARCH=arm64 MODPATH=/m sh -c '
  ui_print(){ :; }; abort(){ echo "ABORT:$*"; exit 9; }
  set_perm(){ echo "$@" >> "'"$log"'"; }
  . ./customize.sh
' || fail "arm64 path aborted unexpectedly"
[ "$(grep -c '/m/system/bin/ffmpeg 0 2000 0755'  "$log")" -eq 1 ] || fail "no ffmpeg set_perm"
[ "$(grep -c '/m/system/bin/ffprobe 0 2000 0755' "$log")" -eq 1 ] || fail "no ffprobe set_perm"

# --- non-arm64: expect abort (exit 9) ---
if ARCH=x86 MODPATH=/m sh -c '
  ui_print(){ :; }; abort(){ echo "ABORT:$*"; exit 9; }
  set_perm(){ :; }
  . ./customize.sh
' 2>/dev/null; then fail "x86 did not abort"; fi

echo "PASS test_customize"
```

- [ ] **Step 2: Run it — must fail (old customize.sh has no arch guard)**

Run: `sh tests/test_customize.sh`
Expected: FAIL (`x86 did not abort` — current script lacks the guard).

- [ ] **Step 3: Rewrite `customize.sh`**

```sh
#!/system/bin/sh
# FFmpeg system-wide (arm64-v8a). $ARCH is the Magisk literal: arm/arm64/x86/x64/riscv64.
ui_print "- FFmpeg system-wide (arm64-v8a)"

if [ "$ARCH" != "arm64" ]; then
  abort "! Unsupported arch '$ARCH' - this module is arm64-v8a only"
fi

set_perm "$MODPATH/system/bin/ffmpeg"  0 2000 0755
set_perm "$MODPATH/system/bin/ffprobe" 0 2000 0755

ui_print "- Installed: ffmpeg, ffprobe"
ui_print "- Test with: ffmpeg -version"
```

- [ ] **Step 4: Run the test — must pass**

Run: `sh tests/test_customize.sh`
Expected: `PASS test_customize`.

- [ ] **Step 5: Lint**

Run: `command -v shellcheck >/dev/null && shellcheck --shell=sh customize.sh || echo "CI enforces"`
Expected: no warnings.

- [ ] **Step 6: Commit**

```bash
git add customize.sh tests/test_customize.sh
git commit -m "feat: customize.sh arch guard + perms for ffmpeg/ffprobe"
```

---

## Task 9 [E]: `COPYING` — GPLv2 text

**Files:**
- Create: `COPYING`

- [ ] **Step 1: Download the canonical GPLv2 text**

Run:
```bash
curl -fsSL https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt -o COPYING
```

- [ ] **Step 2: Verify it is the GPLv2 text (content check, not brittle hash)**

Run:
```bash
head -n3 COPYING | grep -q 'GNU GENERAL PUBLIC LICENSE' && \
grep -q 'Version 2, June 1991' COPYING && echo GPLV2_OK || echo BAD
wc -l COPYING
```
Expected: `GPLV2_OK`; line count ~339.

- [ ] **Step 3: Commit**

```bash
git add COPYING
git commit -m "docs: add GPLv2 COPYING (ffmpeg GPL build)"
```

---

## Task 10 [P]: `action.sh` — Magisk Action button

Requires Magisk v28.0+; best-effort extra. Install floor stays v20.4 (MGK-1). Absolute paths via `MODDIR` (MGK-2).

**Files:**
- Create: `action.sh`
- Test: `tests/test_action.sh`

- [ ] **Step 1: Write the failing test (stubbed binaries, MODDIR resolution)**

Create `tests/test_action.sh`:
```sh
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
out=$(cd "$tmp" && sh action.sh)
echo "$out" | grep -q 'ffmpeg version nTEST'  || fail "ffmpeg line missing"
echo "$out" | grep -q 'ffprobe version nTEST' || fail "ffprobe line missing"
echo "PASS test_action"
```

- [ ] **Step 2: Run it — must fail (action.sh absent)**

Run: `sh tests/test_action.sh`
Expected: FAIL — `cp: cannot stat 'action.sh'`.

- [ ] **Step 3: Implement `action.sh`**

```sh
#!/system/bin/sh
# Magisk Action button (Magisk v28.0+). Prints ffmpeg/ffprobe versions as a smoke test.
# Absolute paths via MODDIR so it does not depend on /system/bin being on PATH (MGK-2).
MODDIR=${0%/*}
"$MODDIR/system/bin/ffmpeg"  -version | head -n1
"$MODDIR/system/bin/ffprobe" -version | head -n1
```

- [ ] **Step 4: Run the test — must pass**

Run: `sh tests/test_action.sh`
Expected: `PASS test_action`.

- [ ] **Step 5: Lint + commit**

```bash
command -v shellcheck >/dev/null && shellcheck --shell=sh action.sh || echo "CI enforces"
git add action.sh tests/test_action.sh
git commit -m "feat: action.sh version button (Magisk v28+)"
```

---

## Task 11 [E]: `scripts/versioncode.sh` — versionCode arithmetic (TDD)

`versionCode = YYYYMMDD*10 + R`, `R` in 0..9 (CI-1/CI-2). The R-derivation (counting today's releases) lives in CI; this script is the pure, testable arithmetic.

**Files:**
- Create: `scripts/versioncode.sh`
- Test: `tests/test_versioncode.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_versioncode.sh`:
```sh
#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
[ "$(sh scripts/versioncode.sh 20260620 0)" = "202606200" ] || fail "base"
[ "$(sh scripts/versioncode.sh 20260620 1)" = "202606201" ] || fail "same-day r1"
[ "$(sh scripts/versioncode.sh 99991231 9)" = "999912319" ] || fail "max bound"
if sh scripts/versioncode.sh 20260620 10 2>/dev/null; then fail "R=10 accepted"; fi
if sh scripts/versioncode.sh 2026062 0 2>/dev/null; then fail "bad date accepted"; fi
echo "PASS test_versioncode"
```

- [ ] **Step 2: Run — must fail (script absent)**

Run: `sh tests/test_versioncode.sh`
Expected: FAIL — `scripts/versioncode.sh: No such file or directory`.

- [ ] **Step 3: Implement `scripts/versioncode.sh`**

```sh
#!/bin/sh
# Host-only. Prints versionCode = YYYYMMDD*10 + R. Usage: versioncode.sh <YYYYMMDD> <R(0..9)>
set -eu
d=${1:-}; r=${2:-}
case "$d" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) echo "bad date (want YYYYMMDD): $d" >&2; exit 1;; esac
case "$r" in [0-9]) ;; *) echo "R must be a single digit 0..9: $r" >&2; exit 1;; esac
echo $(( d * 10 + r ))
```

- [ ] **Step 4: Run — must pass**

Run: `sh tests/test_versioncode.sh`
Expected: `PASS test_versioncode`.

- [ ] **Step 5: Commit**

```bash
git add scripts/versioncode.sh tests/test_versioncode.sh
git commit -m "build: add versioncode.sh (YYYYMMDD*10+R) with tests"
```

---

## Task 12 [E]: `scripts/selftest-zip.sh` — ZIP validator (TDD on device)

Reused by CI (CI-6) and runnable locally. Validates: exactly the two binaries (ignoring `.gitkeep`), arm64 ELF64/AArch64, exec bit, 16KB alignment.

**Files:**
- Create: `scripts/selftest-zip.sh`
- Test: `tests/test_selftest_zip.sh`

- [ ] **Step 1: Write the failing test (build a real ZIP from the fetched binaries)**

Create `tests/test_selftest_zip.sh`:
```sh
#!/bin/sh
# Requires Task 6 to have populated system/bin/{ffmpeg,ffprobe}.
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f system/bin/ffmpeg ] && [ -f system/bin/ffprobe ] || fail "run Task 6 first (binaries absent)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# good zip (excludes .gitkeep, like the real package step)
zip -q -r9 "$tmp/good.zip" META-INF system module.prop customize.sh COPYING -x 'system/bin/.gitkeep'
sh scripts/selftest-zip.sh "$tmp/good.zip" || fail "good zip rejected"

# bad zip: drop ffprobe -> must fail
mkdir -p "$tmp/bad/system/bin"; cp system/bin/ffmpeg "$tmp/bad/system/bin/ffmpeg"
( cd "$tmp/bad" && zip -q -r9 "$tmp/bad.zip" system )
if sh scripts/selftest-zip.sh "$tmp/bad.zip" 2>/dev/null; then fail "bad zip (missing ffprobe) accepted"; fi

echo "PASS test_selftest_zip"
```

- [ ] **Step 2: Run — must fail (script absent)**

Run: `sh tests/test_selftest_zip.sh`
Expected: FAIL — `scripts/selftest-zip.sh: No such file or directory` (or the Task-6 guard if binaries are missing).

- [ ] **Step 3: Implement `scripts/selftest-zip.sh`**

```sh
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
```

- [ ] **Step 4: Run — must pass**

Run: `sh tests/test_selftest_zip.sh`
Expected: `PASS test_selftest_zip`.

- [ ] **Step 5: Commit**

```bash
git add scripts/selftest-zip.sh tests/test_selftest_zip.sh
git commit -m "build: add selftest-zip.sh (arm64 ELF/exec/16KB validator)"
```

---

## Task 13 [E]: `update.json` + `changelog.txt` seed

**Files:**
- Create: `update.json`
- Create: `changelog.txt`

- [ ] **Step 1: Create `update.json`**

```json
{
  "version": "v7.1.1",
  "versionCode": 202606200,
  "zipUrl": "https://github.com/ptrkhh/ffmpeg-magisk-module/releases/download/v7.1.1/FFmpeg-v7.1.1-for-magisk.arm64.zip",
  "changelog": "https://raw.githubusercontent.com/ptrkhh/ffmpeg-magisk-module/main/changelog.txt"
}
```

- [ ] **Step 2: Create `changelog.txt` (in-app, per-release)**

```text
v7.1.1 (2026-06-20)
- Initial release: ffmpeg + ffprobe n7.1.1, GPL (libx264/libx265), arm64-v8a, 16KB-page ready.
```

- [ ] **Step 3: Verify valid JSON and versionCode parity with module.prop**

Run:
```bash
# validate JSON (python is universally present on the runner; falls back if not)
python3 -c "import json,sys;d=json.load(open('update.json'));print('JSON_OK',d['versionCode'])"
grep -q "versionCode=$(python3 -c "import json;print(json.load(open('update.json'))['versionCode'])")" module.prop && echo MATCH || echo MISMATCH
```
Expected: `JSON_OK 202606200` then `MATCH`.

- [ ] **Step 4: Commit**

```bash
git add update.json changelog.txt
git commit -m "feat: updateJson feed + in-app changelog seed"
```

---

## Task 14 [E]: `.github/workflows/release.yml` — CI release pipeline

Publishes only on push tag `v*`; `workflow_dispatch` is a non-publishing dry-run (CI-3). Commit-back uses `GITHUB_TOKEN` (no re-trigger), `pull --rebase`+retry, `release` concurrency (SEC-4). PR-fallback for protected `main` is `[P]` (Task 18).

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Implement the workflow**

```yaml
name: release
on:
  push:
    tags: ["v*"]
  workflow_dispatch: {}

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Lint shell
        run: |
          sudo apt-get update -qq && sudo apt-get install -y shellcheck
          shellcheck --shell=sh customize.sh action.sh scripts/*.sh \
            META-INF/com/google/android/update-binary

      - name: Unit tests
        run: for t in tests/test_*.sh; do echo "== $t =="; sh "$t" || exit 1; done

      - name: Fetch + verify binaries
        run: sh scripts/fetch-ffmpeg.sh

      - name: Assert system/bin holds exactly the two binaries
        run: |
          found=$(find system/bin -maxdepth 1 -type f ! -name '.gitkeep' -printf '%f\n' | sort | tr '\n' ' ')
          test "$found" = "ffmpeg ffprobe " || { echo "unexpected: [$found]"; exit 1; }

      - name: Compute versionCode (strictly increasing; guard folded in)
        id: vc
        run: |
          git fetch origin main --depth=1 || true
          # last published versionCode (seed update.json on main; 0 if none)
          old=$(git show origin/main:update.json 2>/dev/null \
                | grep -oE '"versionCode"[^0-9]*[0-9]+' | grep -oE '[0-9]+$' || echo 0)
          today=$(date -u +%Y%m%d)
          # R = prior same-day release count (spec §12.3): if old is in today's band,
          # increment its R; else reset to 0. Guarantees vc > old (same day) and
          # vc > old (new day, since today*10 > old).
          if [ "$((old / 10))" -eq "$today" ]; then r=$(( (old % 10) + 1 )); else r=0; fi
          [ "$r" -le 9 ] || { echo "more than 10 releases in one day"; exit 1; }
          vc=$(sh scripts/versioncode.sh "$today" "$r")
          test "$vc" -gt "$old" || { echo "versionCode $vc !> published $old"; exit 1; }
          echo "versioncode=$vc" >> "$GITHUB_OUTPUT"
          echo "ffmpeg_version=$(grep '^FFMPEG_VERSION=' ffmpeg.lock | cut -d= -f2)" >> "$GITHUB_OUTPUT"

      - name: Stamp module.prop
        run: |
          v="${{ steps.vc.outputs.ffmpeg_version }}"
          vc="${{ steps.vc.outputs.versioncode }}"
          sed -i -E "s/^version=.*/version=v$v/" module.prop
          sed -i -E "s/^versionCode=.*/versionCode=$vc/" module.prop
          grep -E '^(version|versionCode)=' module.prop

      - name: Package ZIP
        run: |
          v="${{ steps.vc.outputs.ffmpeg_version }}"
          zip -r9 "FFmpeg-v$v-for-magisk.arm64.zip" \
            META-INF system module.prop customize.sh action.sh COPYING \
            -x '*/.git*' -x 'system/bin/.gitkeep'

      - name: Self-test ZIP
        run: |
          sudo apt-get install -y binutils file
          sh scripts/selftest-zip.sh "FFmpeg-v${{ steps.vc.outputs.ffmpeg_version }}-for-magisk.arm64.zip"

      - name: Dry-run stops here
        if: github.ref_type != 'tag'
        run: echo "workflow_dispatch dry-run complete (no release published)"

      - name: SHA256 sidecar
        if: github.ref_type == 'tag'
        run: sha256sum "FFmpeg-v${{ steps.vc.outputs.ffmpeg_version }}-for-magisk.arm64.zip" > SHA256SUMS.txt

      - name: Publish Release
        if: github.ref_type == 'tag'
        uses: softprops/action-gh-release@v2
        with:
          files: |
            FFmpeg-v${{ steps.vc.outputs.ffmpeg_version }}-for-magisk.arm64.zip
            SHA256SUMS.txt

      - name: Refresh update.json + changelog on main
        if: github.ref_type == 'tag'
        run: |
          v="${{ steps.vc.outputs.ffmpeg_version }}"; vc="${{ steps.vc.outputs.versioncode }}"; tag="${{ github.ref_name }}"
          git config user.name  github-actions[bot]
          git config user.email 41898282+github-actions[bot]@users.noreply.github.com
          git fetch origin main && git checkout main && git pull --rebase origin main
          cat > update.json <<EOF
          {
            "version": "v$v",
            "versionCode": $vc,
            "zipUrl": "https://github.com/${{ github.repository }}/releases/download/$tag/FFmpeg-v$v-for-magisk.arm64.zip",
            "changelog": "https://raw.githubusercontent.com/${{ github.repository }}/main/changelog.txt"
          }
          EOF
          { echo "$tag ($(date -u +%Y-%m-%d))"; git tag -l --format='%(contents:body)' "$tag"; } > changelog.txt
          { echo "## $tag ($(date -u +%Y-%m-%d))"; git tag -l --format='%(contents:body)' "$tag"; echo; cat CHANGELOG.md 2>/dev/null; } > CHANGELOG.new && mv CHANGELOG.new CHANGELOG.md
          git add update.json changelog.txt CHANGELOG.md
          git commit -m "release: $tag (versionCode $vc) [skip ci]" || echo "no changes"
          git push origin main || { git pull --rebase origin main && git push origin main; }
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 2: Validate the workflow YAML**

Run:
```bash
command -v actionlint >/dev/null && actionlint .github/workflows/release.yml || \
  python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML_OK')"
```
Expected: `actionlint` clean, or `YAML_OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: tag-triggered release pipeline (fetch, selftest, publish, updateJson)"
```

---

## Task 15 [E]: `README.md` rewrite

**Files:**
- Modify: `README.md` (full rewrite)

- [ ] **Step 1: Replace `README.md`**

````markdown
# FFmpeg Magisk Module (arm64-v8a)

A ready-to-flash Magisk module that installs **ffmpeg** and **ffprobe** system-wide
on arm64-v8a Android devices. Binaries are GPL builds with **libx264/libx265 encode**,
statically self-contained, and **16 KB-page ready** (Android 15/16).

## Install

1. Download the latest `FFmpeg-vX.Y.Z-for-magisk.arm64.zip` from
   [Releases](https://github.com/ptrkhh/ffmpeg-magisk-module/releases).
2. Magisk app → Modules → *Install from storage* → select the ZIP → reboot.

No manual binary step — the ZIP already contains the binaries.

**In-app updates:** the module advertises `updateJson`, so Magisk shows
"Update available" when a new release ships.

## Usage

```bash
ffmpeg -version
ffprobe -version
ffmpeg -i in.mp4 -c:v libx264 -crf 23 out.mp4
```

(On Magisk v28.0+, the module's **Action** button prints the installed versions.)

## Build it yourself

```bash
sh scripts/fetch-ffmpeg.sh          # download+verify the pinned binaries into system/bin/
zip -r9 module.zip META-INF system module.prop customize.sh action.sh COPYING \
  -x '*/.git*' -x 'system/bin/.gitkeep'
sh scripts/selftest-zip.sh module.zip
```

## Bumping ffmpeg

```bash
sh scripts/update-pin.sh <upstream-tag>   # rewrites ffmpeg.lock (owner+TOFU+16KB checks)
git add ffmpeg.lock && git commit -m "build: bump ffmpeg pin"
git tag vX.Y.Z && git push --tags         # CI builds + publishes the Release
```

## Tested on

| Device | Android | Magisk | Result |
|---|---|---|---|
| _(fill in)_ | _(e.g. 14)_ | _(e.g. 27.0)_ | ffmpeg/ffprobe -version OK |

## Requirements

- Magisk v20.4+ (install). Action button needs v28.0+.
- arm64-v8a device. Other arches abort install.
- ~56 MB free under `/data/adb/modules` (two ~28 MB static binaries).
  `ffmpeg`/`ffprobe` are not part of stock Android, so nothing is shadowed.

## License

The bundled `ffmpeg`/`ffprobe` are **GPL** builds (libx264 GPLv2+, libx265 GPLv2+),
so the combined work is **GPLv2-or-later**; `nonfree` is NOT enabled. See `COPYING`.

Binaries are pinned from [yearsyan/ffmpeg-android-build](https://github.com/yearsyan/ffmpeg-android-build)
(see `ffmpeg.lock`). Corresponding source for each release is attached to the GitHub
Release (GPLv2 §3). This module is supplied by a single upstream maintainer with no
independent signature; for stronger provenance, build from source.

## Troubleshooting

- *Won't install ("Unsupported arch")*: device is not arm64-v8a — unsupported.
- *`ffmpeg: not found` after reboot*: confirm the module is enabled in Magisk; check Magisk logs.
- *Action button missing*: requires Magisk v28.0+; use `ffmpeg -version` in a terminal instead.
````

- [ ] **Step 2: Acceptance — no stale manual-flow references (CONS-9)**

Run:
```bash
grep -rniE "place (your|the) .*binary|place your ffmpeg|zip -r ffmpeg-magisk" . \
  --exclude-dir=.git --exclude-dir=docs && echo "FOUND_STALE" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for auto-supply flow + GPL/arch notes"
```

---

## Task 16 [E]: `CHANGELOG.md` seed

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create `CHANGELOG.md`**

```markdown
# Changelog

## v7.1.1 (2026-06-20)
- Initial automated release: ffmpeg + ffprobe **n7.1.1**, GPL (libx264/libx265),
  arm64-v8a, 16 KB-page ready. Binaries pinned from yearsyan/ffmpeg-android-build
  `v7.1-beta.16`, SHA512-verified.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: seed CHANGELOG.md"
```

---

## Task 17 [P]: GPLv2 §3 corresponding-source archiving

Make the distributor (this repo) self-sufficient for GPL source (SEC-6) instead of relying on a third party's mutable tag.

**Files:**
- Modify: `scripts/update-pin.sh` (append a source-archive step)
- Modify: `.github/workflows/release.yml` (attach the archive to the Release)

- [ ] **Step 1: Append source archiving to `update-pin.sh`**

After the `cat > ffmpeg.lock` block, add (before the final `echo`s):
```sh
# GPLv2 §3 (SEC-6): archive the upstream build-script tree at the pinned tag, so a
# later upstream deletion cannot strand corresponding-source. Saved next to the lock.
src_tarball="corresponding-source-$newtag.tar.gz"
curl -fL --proto '=https' --tlsv1.2 -o "$tmp/src.tar.gz" \
  "https://github.com/$REPO/archive/refs/tags/$newtag.tar.gz"
cp "$tmp/src.tar.gz" "$src_tarball"
echo "wrote $src_tarball (upstream build tree @ $newtag)"
```

- [ ] **Step 2: Ignore the large source tarball in git, attach it via CI**

Add to `.gitignore`:
```gitignore
corresponding-source-*.tar.gz
```
In `release.yml`, regenerate it during the run and add it to the `files:` list of the
**Publish Release** step:
```yaml
      - name: Build corresponding-source archive
        if: github.ref_type == 'tag'
        run: |
          tag=$(grep '^UPSTREAM_TAG=' ffmpeg.lock | cut -d= -f2)
          repo=$(grep '^UPSTREAM_REPO=' ffmpeg.lock | cut -d= -f2)
          curl -fL -o "corresponding-source-$tag.tar.gz" \
            "https://github.com/$repo/archive/refs/tags/$tag.tar.gz"
          echo "CS_FILE=corresponding-source-$tag.tar.gz" >> "$GITHUB_ENV"
```
…and append `${{ env.CS_FILE }}` to the release `files:`.

- [ ] **Step 3: Verify + commit**

```bash
command -v shellcheck >/dev/null && shellcheck --shell=sh scripts/update-pin.sh || echo "CI enforces"
git add scripts/update-pin.sh .gitignore .github/workflows/release.yml
git commit -m "build: archive GPLv2 corresponding source per release (SEC-6)"
```

---

## Task 18 [P]: CI doc-lint + PR-fallback for protected `main`

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Add a doc-lint job (wire the CONS-9 grep)**

Add as a separate job that runs on PRs/pushes:
```yaml
  doclint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: No stale manual-flow references
        run: |
          if grep -rniE "place (your|the) .*binary|zip -r ffmpeg-magisk" . \
             --exclude-dir=.git --exclude-dir=docs; then
            echo "stale manual-flow reference found"; exit 1
          fi
```

- [ ] **Step 2: PR-fallback when `main` is branch-protected**

In the *Refresh update.json* step, replace the final `git push` with a guard that
opens a PR if a direct push is rejected:
```sh
          if ! git push origin main 2>/dev/null; then
            br="release-bot/$tag"
            git checkout -b "$br" && git push -u origin "$br"
            gh pr create --base main --head "$br" \
              --title "release: $tag updateJson" --body "Automated updateJson refresh for $tag."
          fi
```
(Requires `gh`, preinstalled on `ubuntu-latest`; `GITHUB_TOKEN` already in env.)

- [ ] **Step 3: Validate + commit**

```bash
command -v actionlint >/dev/null && actionlint .github/workflows/release.yml || \
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml')); print('YAML_OK')"
git add .github/workflows/release.yml
git commit -m "ci: doc-lint gate + PR-fallback for protected main"
```

---

## Final verification (run after all [E] tasks)

- [ ] **Run the whole test suite**

Run: `for t in tests/test_*.sh; do echo "== $t =="; sh "$t" || break; done`
Expected: every test prints `PASS ...`.

- [ ] **Build + self-test a release ZIP locally (arm64 device)**

Run:
```bash
sh scripts/fetch-ffmpeg.sh
zip -r9 /tmp/m.zip META-INF system module.prop customize.sh action.sh COPYING -x '*/.git*' -x 'system/bin/.gitkeep'
sh scripts/selftest-zip.sh /tmp/m.zip
```
Expected: `selftest ok: /tmp/m.zip`.

- [ ] **Confirm no binaries committed**

Run: `git ls-files system/bin/`
Expected: only `system/bin/.gitkeep`.

---

## Spec coverage check (self-review)

- Supply/source/arch/binaries/codecs/update-strategy (§2) → Tasks 4–6, 7, 14.
- Source verification evidence (§3) → Task 6 on-device smoke test.
- `ffmpeg.lock` data-not-code + regex parse (§5, SEC-8) → Tasks 3, 6.
- fetch fail-closed, no `curl|tar`, untouched-on-failure (§6, SEC-3) → Task 4.
- update-pin owner/TOFU/16KB (§6, SEC-2, MGK-7) → Task 5.
- customize arch guard + perms (§7, MGK-3/4) → Task 8.
- module.prop + versionCode scheme/bound (§8, CI-1/2) → Tasks 7, 11.
- updateJson + integrity caveat (§9, CI-9) → Task 13, README.
- action.sh v28 floor + MODDIR (§10, MGK-1/2) → Task 10.
- .gitattributes (§11, CI-8) → Task 1.
- CI triggers/permissions/commit-back/monotonic guard/self-test (§12, SEC-4/7, CI-3/6) → Tasks 12, 14.
- error handling (§13) → Tasks 4, 8, 14 (guards) + README troubleshooting.
- testing/shellcheck `--shell=sh` incl update-binary (§14, CI-7) → Tasks 3–12, 14.
- GPL COPYING + corresponding source (§15, SEC-6) → Tasks 9, 17, README.
- README acceptance grep (§16, CONS-9) → Task 15.
- rollback (§13.1) → documented in spec; operational, no code task.

All `[E]` spec requirements map to a task. `[P]` items (17, 18) cover the deferred-hardening subset.
