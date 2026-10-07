# First real-Mac validation checklist

Use a test profile and a harmless page before relying on Bubbles unattended.

1. Build with `build_macos.command` and launch the app.
2. Grant Accessibility + Input Monitoring, quit Bubbles, and relaunch it.
3. Open two Chrome windows; verify Bubbles lists them and controls only the selected one.
4. Routine A: Target 8, Return 1. Confirm the expected tab is clicked and Chrome returns to tab 1.
5. Routine B: Target 5, Return None. Confirm Chrome remains on tab 5.
6. Test a rectangle and square on each connected monitor, including a monitor left of the primary display.
7. Hold the mouse button while a click becomes due. Confirm Bubbles waits/retries rather than creating a drag.
8. During a protected action, press F12. Confirm input is released and the mouse button is not left down.
9. Test F9 Stop while a click is active.
10. Run two routines with colliding due times. Confirm actions occur one at a time.
11. Put the main window into Mini/menu-bar-only mode with Auto Start/Stop armed. Confirm timers remain armed.
12. Test Auto Start by duration and by exact UTC+1 clock time.
13. Test Auto Stop by duration and exact clock time.
14. Change the clock to UTC-5 and +05:30; confirm displayed time and exact timers match that offset.
15. Sleep the Mac long enough to cross a due action. Wake it and confirm Bubbles skips missed actions instead of burst-clicking.
16. Leave a test configuration running for 12+ hours and review the activity log for retries/errors.

If any step fails, keep the profile and send the exact error/message plus a screenshot. The macOS-specific path can then be corrected without changing the shared scheduler model.
