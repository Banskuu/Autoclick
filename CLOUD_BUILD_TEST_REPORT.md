# Apple Silicon cloud-build validation

Validated here:
- Swift package tests: PASS
- macOS ARM64 parser: PASS for 11 source files
- Packaging shell syntax: PASS
- Workflow runner: `macos-15` (Apple Silicon ARM64)
- Workflow produces DMG + app ZIP
- Packaging explicitly refuses a non-arm64 runner

Not possible in this Linux environment:
- Linking/running AppKit and Quartz on macOS
- Executing `hdiutil`, `codesign`, `sips`, `iconutil`

Those steps are intentionally performed by GitHub Actions on a real Apple
Silicon macOS runner.
