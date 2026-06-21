#!/system/bin/sh
# shellcheck disable=SC2154
# FFmpeg system-wide (arm64-v8a). $ARCH is the Magisk literal: arm/arm64/x86/x64/riscv64.
ui_print "- FFmpeg system-wide (arm64-v8a)"

if [ "$ARCH" != "arm64" ]; then
  abort "! Unsupported arch '$ARCH' - this module is arm64-v8a only"
fi

set_perm "$MODPATH/system/bin/ffmpeg"  0 2000 0755
set_perm "$MODPATH/system/bin/ffprobe" 0 2000 0755

ui_print "- Installed: ffmpeg, ffprobe"
ui_print "- Test with: ffmpeg -version"
