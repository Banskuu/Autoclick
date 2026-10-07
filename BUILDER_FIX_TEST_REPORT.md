# macOS 0.2 builder validation

- Swift package tests: PASS
- `build_macos.command` shell syntax: PASS
- `run_tests.command` shell syntax: PASS
- macOS arm64 parser check: PASS for 11 Swift source files
- Builder source permission: 0o755
- Swift tools requirement: 5.9

The environment here is Linux, so AppKit/Quartz cannot be linked and launched.
The important change is that the Mac builder now exposes any real Mac-side
compile/runtime error in `build_macos.log` instead of disappearing.
