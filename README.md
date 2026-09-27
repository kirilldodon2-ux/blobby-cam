# Blobby Cam

Blobby Cam is a native macOS webcam experiment. Apple Vision tracks your left eye, right eye, nose, mouth, and hands. Each live crop appears in its own real macOS window, which you can drag and resize independently.

The primary control surface is an ASCII menu in Terminal. The optional **Goofy UI** shows the same controls in a separate fixed-size window.

## Status

**Developer preview.** The local Debug and Release builds and automated tests pass on an Apple silicon Mac. A signed, notarized release and one-command GitHub installer are not available yet. See [QA_NOTES.md](QA_NOTES.md) for live checks still required before a public release.

## Requirements

- macOS 14 or later
- A webcam and camera permission
- Full Xcode installed (current development build verified with Xcode 27)

No package manager, web runtime, account, or third-party runtime dependency is required.

## Run locally

Open Terminal in the project folder and run:

```sh
./blobby-cam
```

The script builds the macOS app with Xcode and launches it in the same Terminal session. It may take longer on the first run. If Xcode is installed at a nonstandard location, set `DEVELOPER_DIR` to its `Contents/Developer` directory before running the script.

Blobby Cam requests camera access and starts **LIVE** automatically. The camera frames are processed locally. It does not upload or record video.

## Controls

| Key / action | Result |
|---|---|
| ↑ / ↓ | Select a menu row |
| ← / → | Toggle or adjust the selected value |
| Enter on a feature | Open that window's settings |
| Enter on ENABLED or FREEZE FRAME | Toggle that feature setting |
| Esc | Return to the main menu |
| QUIT or Ctrl-C | Stop the app and restore Terminal |
| Drag a feature titlebar | Place that window manually |
| Drag a feature edge | Resize the window without changing its crop |
| Close a feature with its red button | Set that feature to OFF |

**AUTO FOLLOW** defaults to OFF: window positions stay where you put them while their video crops follow your features. **MIRROR** defaults to selfie orientation. **SMOOTHING** defaults to 0, so crop centers follow current detections. **AUTO CROP SCALE** defaults to OFF, keeping facial crop magnification steadier during expressions. Each feature has ON/OFF, FREEZE FRAME, window size and placement, crop zoom/pan/padding, and detection controls. The eye crop zoom defaults to 0.50×.

FREEZE FRAME holds that feature's last crop while the others stay live. A frozen window remains visible if LIVE is switched OFF; ordinary feature windows hide. `SHOW GOOFY UI` opens the optional graphical menu.

## Build and test

```sh
xcodebuild -project BlobbyCam.xcodeproj -scheme BlobbyCam -destination 'platform=macOS' build
xcodebuild -project BlobbyCam.xcodeproj -scheme BlobbyCam -destination 'platform=macOS' test
```

Xcode build output is ignored by Git. The local launcher stores its build under `.build/DerivedData`.

## Small local preview package

The Release app is about 2.7 MB on the tested Mac. The multi-gigabyte `.build` folder is Xcode's local cache and is not part of the app or Git repository.

```sh
./scripts/package-preview.sh
./scripts/install-preview.sh
```

The first command creates an **unsigned** architecture-specific ZIP and SHA-256 file in `dist/`. The second verifies the checksum, installs the app in `~/.local/share/blobby-cam`, creates `~/.local/bin/blobby-cam`, and starts the Terminal UI. Use `--no-run` to install without launching. Add `~/.local/bin` to your shell's `PATH` if you want to type `blobby-cam` from any directory. These preview scripts still require Xcode to **build** the package; the installed app does not rebuild on launch.

The preview package is for local development. Public downloads need a signed and notarized app, a hosted release, and a verified install command.

## How it works

One `AVCaptureSession` produces camera frames. Apple Vision finds face landmarks and hand poses. A shared Core Image / Metal-backed renderer crops those frames into six persistent `NSPanel` windows. There is no per-frame JPEG/PNG conversion or per-feature camera session.

The [build plan](BLOBBY_CAM_BUILD_PLAN.md), [research handoff](fun-tracking.md), and [TUI ASCII kit](Design/dodon-tui-ascii-kit.md) document the design history. The running app and tests are the reference for current behavior.
