# Bubbles Autoclicker — macOS Apple Silicon

**Recommended build method:** GitHub Actions. See `APPLE_SILICON_START_HERE.md`.

# Bubbles Autoclicker — macOS native port (0.3)

This is the first native macOS port of the Windows AutoHotkey Bubbles Autoclicker. It is written in Swift/SwiftUI and builds into **Bubbles Autoclicker.app** with no AutoHotkey or Python dependency.

## Build the .app on a Mac

1. macOS 13 Ventura or newer is recommended.
2. If needed, install Apple's free command-line tools: `xcode-select --install`.
3. Double-click **build_macos.command** (or right-click → Open). The 0.2 builder stays open and shows the exact error if anything fails.
4. The finished app is created at `dist/Bubbles Autoclicker.app`.
5. On first launch, open **Chrome / Settings** and grant:
   - Accessibility
   - Input Monitoring
6. Re-open Bubbles after macOS grants those permissions, refresh Chrome windows, and select the exact Chrome window.

The local build is ad-hoc signed. For public distribution, use an Apple Developer ID certificate + notarization later.

## Behavior carried over from the Windows app

- Multiple independent profiles.
- Multiple routines active at the same time; actual clicks are serialized through one automation worker.
- Per-routine Chrome Target tab (1–9) and optional Return tab. `None` leaves Chrome on the target tab.
- Routine repeat interval + start offset.
- Areas with screen-coordinate click regions, Rectangle/Square selection, At+ anchor and ± timing.
- Fixed, Shuffle Slots and Random Time order modes.
- Random Time groups, minimum spacing, All / Exact / Min-Max subset selection.
- Randomness presets and editable timing/coordinate/click-hold variability.
- Gradual cursor movement, random click point, random mouse-down hold time.
- Selected Chrome-window control and focus verification before the click.
- Physical mouse-button busy wait before protected automation.
- System-wide input protection during the Chrome sequence using a macOS Quartz event tap.
- F9 Stop, F10 Quit, F12 Emergency Release; Ctrl+F8 Start. F11 opens Settings.
- Pause freezes scheduler deadlines and Resume shifts them forward.
- Sleep/stall protection: a long timer gap skips overdue schedules rather than burst-catching up.
- Auto Start / Auto Stop by duration or exact clock moment.
- Configurable UTC offset, default UTC+1.
- Mini window + menu-bar operation.
- Automatic JSON backups and transactional config writes.
- Diagnostics, recent-activity log, Preview 10 Cycles, Test Routine Fast, Random Window helper.

## macOS-specific differences

- macOS requires explicit **Accessibility** and **Input Monitoring** permission. Without them, protected clicking is intentionally blocked.
- Chrome window selection is tracked by Chrome process ID + Accessibility window index/title. Like the Windows HWND approach, closing/reopening Chrome can invalidate the selection and require re-selection.
- Windows `BlockInput` is replaced by a Quartz event tap. Bubbles-generated events carry a private marker and are allowed through while physical mouse/keyboard events are temporarily suppressed.
- The app restores the previously frontmost app/window after the Chrome action using macOS Accessibility APIs.
- macOS privacy permissions and event-tap behavior must be verified on a real Mac. This build environment is Linux and cannot execute AppKit/Quartz runtime behavior.

## Files and settings

Profiles and backups live in:

`~/Library/Application Support/Bubbles Autoclicker/`

Profiles are JSON, so they are much easier to inspect/recover than binary settings.

## Current validation

The shared scheduler/planning core is compiled and unit-tested on Swift 6.2. The macOS source is also parsed with a macOS target to catch syntax errors. The final AppKit/Quartz type-check, permissions, Chrome focus, event-tap input blocking, and actual `.app` execution require macOS and are therefore the first things to verify on a Mac.


## 0.2 builder fix

The 0.1 builder used immediate-exit behavior, so a failed Swift/Xcode command
could make the Terminal window disappear and look like nothing happened.

0.2 now keeps the window open, writes `build_macos.log`, checks the developer
tools first, supports Swift 5.9+, validates the app bundle, and includes
`IF_BUILD_DOES_NOT_OPEN.txt` as a Finder-permission fallback.


## 0.3 one-click Mac builder

You no longer need to launch `build_macos.command` or use Terminal.

1. Double-click **Bubbles Builder.app**.
2. If macOS blocks it, **right-click → Open → Open** once.
3. A dialog saying **Bubbles Builder started** appears immediately.
4. The builder checks Apple's developer tools, builds Bubbles, and opens the
   finished `dist` folder.
5. If anything fails, it shows an error dialog and puts
   `Bubbles_Build_Log.txt` on your Desktop.

The `.command` builder is still included only as a fallback.
