# ADB device inspection (Windows)

Install official Android SDK Platform-Tools, enable USB debugging on your
authorized test device, connect USB and approve the device's authorization
prompt. Tools → ADB Device Inspector → select trusted adb.exe → confirm
authorization → refresh devices. Offline and unauthorized devices cannot
be selected. Device model/manufacturer/Android version/API/ABI, third-party
installed package names and selected package APK paths are read-only.

Launch the selected app yourself before requesting logs. A single main PID
is required; logcat is filtered by that PID and requests up to 300 recent
buffer entries, with a second PID check. This is not continuous tracing;
PID reuse or missing log buffers can affect attribution. Logs may contain
sensitive data. Nothing is automatically sent to AI or network services.

Fixed commands only, explicit serial, validated package/PID, no shell
composition, 25-second per-command timeout, 512 Ki characters per stream.
The ADB server may start as part of normal ADB operation. No root,
arbitrary command execution, install/uninstall, APK pull, debugger,
instrumentation or network interception is implemented. ADB is not bundled.
Real USB/device validation is pending; tests cover output parsing and
argument construction.
