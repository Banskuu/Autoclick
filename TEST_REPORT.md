# Bubbles macOS 0.1 — validation report

## What was executed in this environment

- `swift test` on Swift 6.2.1 / Linux: **8 tests passed, 0 failed**.
- `swift build -c release`: **passed** for the shared core + non-macOS fallback executable.
- `swiftc -frontend -parse -target arm64-apple-macosx13.0 ...`: **passed**, so the active macOS Swift source has no parser/syntax errors.
- Static conditional-compilation scan: all `#if` / `#endif` blocks balanced.

## Core test coverage

- UTC offset parsing (`UTC+1`, half-hour offsets, negative offsets, ±14:00 boundaries).
- UTC/display round trips across the supported offset range.
- Per-routine Target tab and optional Return tab data model.
- Shuffle Slots preserves the original timing slots.
- Random Time boundary and minimum-spacing validation across 1,000 cycles.
- Exact random-subset selection.
- Random Min-Max 4–10 reaches every count across 5,000 cycles.
- Profile JSON encode/decode round trip.

## Source-level macOS checks

The macOS implementation includes:

- SwiftUI native UI and menu-bar extra.
- AppKit/Accessibility Chrome window enumeration and focus/raise.
- Quartz synthetic keyboard/mouse input.
- Quartz event-tap physical-input suppression with synthetic-event marker.
- F9/F10/F12/Ctrl+F8 and F11 handling.
- Random click hold with guaranteed mouse-up cleanup.
- Serialized one-at-a-time action execution.
- sleep/stall missed-schedule skip logic.
- Auto Start / Auto Stop and configurable UTC-offset clock.
- profiles, backups, export/import, monitor-layout check and diagnostics.

## What cannot be validated here

This environment is Linux, not macOS, so it does **not** have Apple's macOS SDK/AppKit runtime. Therefore these require the first real-Mac build/test:

- full AppKit/Quartz type-check/link against the installed macOS SDK,
- Accessibility and Input Monitoring permission prompts,
- exact Chrome Accessibility window behavior,
- event-tap physical input suppression,
- real global hotkeys while other applications are focused,
- multi-monitor Quartz coordinate behavior,
- signing/Gatekeeper behavior,
- 12+ hour native macOS runtime stress.

Use `MAC_TEST_CHECKLIST.md` after building on the Mac. Any Mac-specific error can then be fixed against the exact compiler/runtime message without changing the already-tested shared scheduler core.
