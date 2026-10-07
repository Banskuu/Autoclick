# Bubbles Autoclicker — easiest Apple Silicon build

This project is set up so **GitHub builds the Mac app for you on a real
Apple Silicon Mac**. You do not need Xcode, Swift, Terminal, or the old
`build_macos.command` workflow on your own Mac.

## Once the project is in a GitHub repository

1. Open the repository on GitHub.
2. Click **Actions**.
3. Click **Build Bubbles for Apple Silicon**.
4. Click **Run workflow** → **Run workflow**.
5. Wait for the green check mark.
6. Open that workflow run.
7. Under **Artifacts**, download:
   - `Bubbles-Autoclicker-Apple-Silicon-DMG`
8. Unzip the downloaded GitHub artifact.
9. Open the `.dmg`.
10. Drag **Bubbles Autoclicker.app** into **Applications**.

On the first launch, macOS may require **right-click → Open** because this
private build is ad-hoc signed rather than Apple-notarized.

Bubbles also needs the macOS privacy permissions required for mouse/keyboard
automation, including Accessibility/Input Monitoring.

## Target

- Native architecture: **arm64**
- Runner: **GitHub Actions macOS 15 Apple Silicon**
- Minimum app OS remains: **macOS 13**
- Output: `.dmg` plus a `.app` ZIP
