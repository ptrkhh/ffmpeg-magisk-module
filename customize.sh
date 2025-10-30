#!/system/bin/sh

# FFmpeg System-wide Installation Script

ui_print "- Installing FFmpeg system-wide..."

# Set proper permissions for ffmpeg binary
if [ -f "$MODPATH/system/bin/ffmpeg" ]; then
    ui_print "- Setting permissions for ffmpeg binary..."
    set_perm $MODPATH/system/bin/ffmpeg 0 2000 0755
    ui_print "- FFmpeg installed successfully!"
    ui_print "- You can now use 'ffmpeg' command system-wide"
else
    ui_print "! WARNING: ffmpeg binary not found in module!"
    ui_print "! Please place your ffmpeg binary in system/bin/"
    ui_print "! and reflash this module"
fi

ui_print "- Installation complete!"
