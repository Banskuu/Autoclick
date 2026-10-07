# Bubbles macOS 0.3 one-click builder validation

Passed in this environment:
- Shared Swift package tests
- Shell syntax for Builder.app executable
- Shell syntax for Builder Test.app executable
- Existing fallback `.command` launchers
- XML validation for all Info.plist files
- macOS ARM64 parser validation for 11 Swift source files
- App-bundle executable bits prepared as 0755

The macOS AppKit/Quartz app itself still has to be linked and run on a real Mac.
The new Builder.app is specifically designed so you no longer need Terminal.
If Mac-side compilation fails it writes `Bubbles_Build_Log.txt` to Desktop.
