#!/system/bin/sh
# Magisk Action button (Magisk v28.0+). Prints ffmpeg/ffprobe versions as a smoke test.
# Absolute paths via MODDIR so it does not depend on /system/bin being on PATH (MGK-2).
MODDIR=${0%/*}
"$MODDIR/system/bin/ffmpeg"  -version | head -n1
"$MODDIR/system/bin/ffprobe" -version | head -n1
