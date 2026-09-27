# Blobby Cam TUI integration decisions

Reference artwork: `dodon-tui-ascii-kit.md` in this folder. The user's messages take precedence over example copy in the kit.

- Show the large `dodon.one` ASCII banner during GitHub installation and app loading only. Do not leave it in the running control menu.
- Show a compact rainbow-colored `dodon.one` link near the bottom of the running main/detail TUI.
- Use the kit's main menu, feature detail, and loading-screen composition as the visual reference. Keep the existing keyboard actions and live state contracts.
- Display real camera state: `IDLE`, `STARTING`, `LIVE`, `DENIED`, or `ERROR`, with truthful captions. The kit's `30% installing...` is illustrative; do not invent progress percentages.
- Preserve pink selected row (`>`) and persistent pink active toggles. The layout must remain usable in an 80×24 Terminal.
- The current input/autolive bugfix must pass before restyling the renderer. Default `AUTO FOLLOW = OFF` and user-dragged static window placement are the next separate product correction.
- Public distribution target: one Terminal command downloads a signed/notarized GitHub release, installs it without Xcode, and immediately runs the bundled executable with stdin attached to the controlling TTY. The local `./blobby-cam` command remains a developer launcher. Publish only after live QA and release gates pass.
