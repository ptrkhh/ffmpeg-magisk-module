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
