# FFmpeg Magisk Module

A ready-to-flash Magisk module that installs FFmpeg system-wide on Android devices.

## Installation Instructions

The module is ready to flash, but you need to add the ffmpeg binary first:

1. Add your ffmpeg binary to the `system/bin` folder
    - The binary should be named: ffmpeg
    - Make sure it's executable and compatible with your device architecture (arm64-v8a recommended for modern devices)
2. Make sure the binary is executable: `chmod 0755 system/bin/ffmpeg`
3. Compress the folder: `zip -r ffmpeg-magisk-module.zip . -x '.*' -x '*/.*'`
4. Flash via Magisk Manager:
   - Open Magisk Manager
   - Tap on "Modules"
   - Tap "Install from storage"
   - Select the ZIP file
   - Reboot when prompted

## Usage

After installation and reboot, ffmpeg will be available system-wide:

```bash
# Test installation
adb shell ffmpeg -version

# Or in terminal emulator e.g. Tasker Run Shell Command
ffmpeg -version
```

## Module Structure

```
ffmpeg-magisk-module/
├── META-INF/
│   └── com/google/android/
│       ├── update-binary
│       └── updater-script
├── system/
│   └── bin/
│       └── ffmpeg (place your binary here)
├── module.prop
└── customize.sh
```

## Requirements

- Magisk v20.4 or higher
- ARM/ARM64 Android device
- Compatible ffmpeg binary for your architecture

## Notes

- The module uses Magisk's systemless mounting
- No actual system partition modification
- Can be easily removed via Magisk Manager
- Binary must be ARM/ARM64 compatible
- Recommended: arm64-v8a binary for modern devices

## Troubleshooting

If ffmpeg doesn't work after installation:
1. Verify the binary is actually in the ZIP before flashing
2. Check binary permissions (should be 0755)
3. Verify binary architecture matches your device
4. Check Magisk logs in Magisk Manager

## License

This module structure is provided as-is. FFmpeg binary licensing depends on the source you obtain it from.
