# T19 Stability and Acceptance QA

Date: 2026-09-26

## Window motion correction — implemented, live check pending

The user reported that the previous build moved panels with their head and snapped back after a mouse drag. The current source now defaults `AppState.follow` to `false`; deterministic static-placement and native-resize tests pass. A fresh real-camera check is still required.

- Default: feature **video crops continue tracking** eyes, nose, mouth, and hands, while the six native feature **window frames stay fixed on screen** in an initial nonoverlapping layout similar to the supplied screenshot.
- Users can drag each feature window to any preferred screen position; the app must preserve that manual placement during live updates and resize.
- `AUTO FOLLOW` is an optional Terminal menu control and defaults to **OFF**. When enabled, feature windows may move with tracked positions; turning it off freezes their current positions without interrupting live crop tracking.
- Verify that head/hand movement with AUTO FOLLOW OFF changes video content but never moves window frames, and that manual placement remains stable.

## Scope and environment

The original T19 pass ran noninteractive checks. A later user run confirmed that a real Terminal command could start the app and display live, moving feature windows, but its TUI disappeared and manual placement snapped back. Those bugs were changed after that report. The updated build has passed automated tests; a new Terminal.app, camera, display, and ten-minute live check is still pending.

## Automated test gate

Command:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project BlobbyCam.xcodeproj \
  -scheme BlobbyCam \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

Latest integrated result: **PASS — 99 tests, 0 failures, 0 skipped.** The run completed on 2026-09-26 and produced `.build/DerivedData-Integrated/Logs/Test/Test-BlobbyCam-2026.09.26_19-58-37-+0300.xcresult`.

The 18:09 user screenshots confirmed live crops and Terminal arrow input in a large window, but exposed diagonal TUI rows and loss of the menu after resizing to 80×24. Raw-mode redraw now emits CRLF, reads the current TTY dimensions, fits the menu to at most 52 columns, and redraws on resize. Left/Right on any feature's main-menu row toggles its ON/OFF state; Enter opens its detail page. The user's ASCII kit is used for a truthful camera loading view. These changes passed automated tests but need a fresh Terminal.app run.

The 18:20 user screenshots confirmed the compact TUI and live face windows, then showed that opening the mouth caused the crop to zoom out. `AUTO CROP SCALE` is now a global Terminal and Goofy UI switch, OFF by default and after RESET. When OFF, face crop dimensions are based on face-box size and the crop center still tracks facial landmarks; when ON, the previous landmark-bounds sizing is restored. Deterministic tests cover both modes. A fresh live-expression check remains pending.

The latest pass sets default smoothing to 0 and both eye crop zooms to 0.50×. Camera LIVE starts automatically from Terminal and GUI launches. LIVE has a discrete rainbow treatment when active, and the Terminal home footer identifies Enter as the path to window settings. A native red close action now marks that feature OFF in shared state while preserving its panel instance. Each feature has FREEZE FRAME in Terminal detail and Goofy UI; freezing retains that feature's last camera frame while other crops continue updating. Frozen panels retain their frame when LIVE is switched OFF; ordinary panels hide. Tests cover shared state, menu actions, close behavior, panel identity, frozen-frame retention, detection loss, and LIVE OFF. Physical camera/UI checks remain pending.

The 19:55 live screenshot caught a regression: with smoothing set to 0, the implementation interpolated with alpha 0 and held the first landmark position, so eyes/nose/mouth drifted out of their crops when the face moved. Smoothing 0 now uses the current detection; higher settings interpolate while still moving at maximum smoothing. New tests cover both endpoints. The Terminal home screen also used 24 lines while the session safely renders 23 in an 80×24 window, clipping the navigation guide. It now fits the guide and all controls in 23 lines; a standard-size renderer test covers the full frame. Live confirmation of both fixes remains pending.

Relevant deterministic coverage includes permission mapping and denied capture behavior (`CameraPermissionTests`, `CameraCaptureTests`), frame replacement/backpressure (`LatestFrameStoreTests`, `VisionTrackerTests`), face and hand geometry (`FaceRegionExtractorTests`, `HandRegionExtractorTests`), smoothing/grace timing (`TrackingSmootherTests`), screen/mirror geometry (`ScreenMapperTests`), persistent panel identity/resize/non-overlap (`FeatureWindowManagerTests`, `IntegrationStateTests`), renderer crop geometry (`RendererGeometryTests`), and Terminal controls/session cleanup (`TerminalMenuTests`, `TerminalKeyParserTests`, `ControlIntegrationTests`).

## Source audit

Commands used:

```sh
rg -n 'CameraCapture|AVCaptureSession|AVCaptureVideoDataOutput|AVCaptureDeviceInput' BlobbyCam --glob '*.swift'
rg -ni 'NSImage|UIImage|NSBitmapImageRep|CGImageSource|CGImageDestination|jpegData|pngData|kUTTypeJPEG|kUTTypePNG' BlobbyCam --glob '*.swift'
rg -n 'FeaturePanel|NSPanel|makeRenderView|installRenderView' BlobbyCam --glob '*.swift'
rg -n 'onHover|mouseEntered|mouseMoved|mouseExited' BlobbyCam --glob '*.swift'
```

Findings:

- **One capture pipeline — PASS (source audit).** `AppDelegate.configureTracking()` constructs one `CameraCapture`. That owns one `AVCaptureCameraPipeline`; its worker owns one `AVCaptureSession` and one `AVCaptureVideoDataOutput`. Output installation is guarded by `outputWasAdded`, and `alwaysDiscardsLateVideoFrames` is enabled. The single source construction path is in `BlobbyCam/Camera/CameraCapture.swift`.
- **No per-frame JPEG/PNG/NSImage conversion — PASS (source audit).** No matching image encoder, `NSImage`, `UIImage`, or bitmap-representation path was found. `SharedRenderer.update` wraps the current `CVPixelBuffer` in one `CIImage` and creates lazy crop graphs that share it; one `CIContext` renders those crops. This is a source audit, not an Instruments allocation trace.
- **No per-frame panel construction — PASS (source and identity tests).** `FeatureWindowManager.init` creates the six `FeaturePanel` instances. Its frame application path looks them up with `panel(for:)`; it does not construct panels. `FeatureWindowManagerTests` and `IntegrationStateTests` verify the six object identities persist through repeated apply/show/hide/resize operations. No Instruments allocation count was captured.
- **No hover magnification hooks found — source audit only.** No hover/mouse-enter handler changes panel scale, crop zoom, or frame. The requested live pointer sweep was not performed.

## Acceptance matrix

`PASS` means the row's stated check is covered by the listed deterministic test or source inspection. `BLOCKED` means a required live/manual/runtime portion remains unverified, even when automated coverage passed.

| Area | Status | Evidence / remaining check |
|---|---|---|
| Camera permission allow | BLOCKED | Permission service grant path is unit tested; a fresh real TCC prompt and camera start were not exercised. |
| Camera permission deny | BLOCKED | Fake denial stays noncapturing, and ASCII status rendering is tested; actual denial state/panel cleanup on a webcam is unverified. |
| Camera start | BLOCKED | Source has one session/output and fake pipeline tests pass; hardware timestamps and live frames were not observed. |
| Camera stop/reconnect | BLOCKED | Fake stop/interruption recovery is tested; physical reconnect/interruption was not tested. |
| Left eye | BLOCKED | Face geometry/crop tests pass; live crop and displayed-left correctness need a face check. |
| Right eye | BLOCKED | Face geometry/crop tests pass; live crop and displayed-right correctness need a face check. |
| Nose | BLOCKED | Face geometry tests pass; live crop and position were not observed. |
| Mouth | BLOCKED | Face geometry tests pass; speech/motion behavior was not observed. |
| Left hand | BLOCKED | Chirality maps identity independently of horizontal position in unit tests; two-hand crossing on camera was not checked. |
| Right hand | BLOCKED | Chirality maps identity independently of horizontal position in unit tests; two-hand crossing on camera was not checked. |
| Six real windows | PASS | Six distinct persistent `NSPanel` identities, native controls, and repeated show/hide are asserted by `FeatureWindowManagerTests`; visible live content remains unverified. |
| Native Terminal-like chrome | BLOCKED | Panel style/titlebar/dark appearance properties are asserted in tests; visual comparison on the unlocked desktop was not possible. |
| No overlap | PASS | Deterministic integration test lays out six coincident targets without overlap and avoids the optional menu frame. |
| Window size | BLOCKED | Resize persistence across frames is tested on a panel; manual drag/size reporting/reset for all six panels remains. |
| Window position | BLOCKED | Geometry and action state are tested; live Terminal X/Y adjustment with the displayed panel remains. |
| Crop/padding | BLOCKED | Crop geometry and crop/window independence are tested; live Terminal adjustment remains. |
| Crop zoom/pan | BLOCKED | Bounded crop geometry and independent state are tested; pupil-to-eye/brow framing needs a live eye check. |
| Detection | BLOCKED | Confidence/geometry eligibility is unit tested; real-camera threshold response was not observed. |
| Native feature resize | BLOCKED | Integration tests simulate AppKit resize callbacks and verify the size persists across frames; a physical edge-drag with live video remains. |
| Static panels by default | BLOCKED | `AppState.follow` defaults/resets to OFF; integration tests hold panel frames through moving detections and manual frame changes. Real mouse drag/head movement on the updated build remains. |
| Primary ASCII menu | BLOCKED | Renderer and production-PTY integration tests verify 80×24 output and arrow/Enter actions. A real interactive Terminal.app run is still required to verify focus transfer and live panels. |
| TUI selection/active color | BLOCKED | Renderer test verifies pink selected/active rows and `>` marker; local terminal color rendering was not observed. |
| Terminal cleanup | BLOCKED | Production-PTY integration restores ICANON/ECHO/ISIG, and injected session tests verify cursor/alternate-screen cleanup; actual Terminal.app Ctrl-C cleanup remains. |
| Optional Goofy UI | BLOCKED | Source creates the fixed-size menu lazily and state is shared; TTY show/hide/close behavior could not be exercised. |
| No hover magnification | BLOCKED | Source audit found no hover magnification handler; the required pointer sweep/frame observation remains. |
| Smoothing | BLOCKED | Deterministic EMA, reacquisition, and stale-snapshot tests pass; camera jitter needs a live check. |
| Short loss grace | BLOCKED | Timestamp tests verify hold/fade/hide timing; brief live detection loss was not observed. |
| Semantic hands | BLOCKED | Synthetic chirality/position tests pass; crossed-hand camera behavior remains. |
| Mirror correctness | BLOCKED | Unit tests verify default selfie mapping and single screen-placement flip; live eye/hand view and mirror toggle remain. |
| Keyboard focus | BLOCKED | TTY startup now returns activation to the app that was frontmost before Blobby Cam, and panels are nonactivating; confirm arrows remain usable with live panels in Terminal.app. |
| Spaces/full-screen | BLOCKED | Panel collection behavior is set in source; multi-Space/full-screen operation was not available to inspect. |
| Retina | BLOCKED | Synthetic 1×/2× geometry tests pass; non-1× hardware rendering remains. |
| External display | BLOCKED | Negative-origin/external-screen geometry tests pass; actual two-display placement remains. |
| Memory plateau | BLOCKED | No ten-minute live run or Activity Monitor/Instruments record was possible. |
| No per-frame image conversion | BLOCKED | Source audit found no image encoding/`NSImage` conversion path; required allocation trace was not captured. |
| One capture pipeline | PASS | Source audit finds one app-level `CameraCapture`, one worker-owned `AVCaptureSession`, and one video output. Runtime device inspection remains part of the camera smoke. |
| No per-frame window recreation | BLOCKED | Source and identity tests show stable six panels; runtime allocation-count profiling was not performed. |

The latest deterministic gate is green. The earlier App Sandbox raw-mode error was removed; a later user run started TUI and live panels but found TUI disappearance and moving panels. The current build includes input lifecycle, static-panel, and kit-renderer changes; their live behavior remains to be checked in Terminal.app.

## Reproducible checks still required

Run these from an unlocked Mac in Terminal.app. The local launcher rebuilds the current checkout, then `exec`s the app executable in the same process:

```sh
cd ~/Desktop/blobby-cam
./blobby-cam
```

1. Confirm startup shows the kit loading view followed by the compact ASCII menu, no Goofy window, and Terminal retains focus. Resize Terminal from fullscreen to 80×24 and back; lines must stay aligned and the selected row visible. Navigate every global row and feature detail row with Up/Down, Left/Right, Enter, and Escape. Verify selected pink with `>` and active toggles stay pink after moving selection; LIVE ON should be rainbow. Enter on NOSE should open its detail page, where FREEZE FRAME is available. Select NOSE on the home screen and use Left/Right to hide/show its panel.
2. LIVE starts automatically from a TTY or GUI launch. Check the real camera allow flow and increasing frame timestamps. Run the denial case from a fresh permission state with `tccutil reset Camera com.blobbycam.BlobbyCam`, launch again, deny the prompt, and verify `ACCESS DENIED` remains visible with no live panels. Re-enable permission and verify stop/start and interruption/reconnect.
3. With a face and both hands visible, verify left/right eyes, nose, mouth, semantic left/right hands through crossing, mirror toggle, crop/padding/zoom/pan, detection threshold, and brief-loss grace.
4. Drag each panel edge while live; verify video fills the new content area, the size persists across frames, Terminal reports it, and reset restores the default. Adjust panel X/Y and verify no overlap.
5. Run `SHOW GOOFY UI`, then hide it and close it with its titlebar control. Confirm there is at most one fixed-size GUI window, Terminal remains usable, and camera capture continues. In another shell, `pgrep -fl '/BlobbyCam.app/Contents/MacOS/BlobbyCam'` should report one app process. Close NOSE via its native red titlebar button; verify NOSE turns OFF in both UIs and can be re-enabled without creating another panel.
6. Freeze LEFT EYE from Terminal detail. Blink or move while LEFT EYE remains static and other live crops update; unfreeze and verify it resumes. Repeat using the Goofy UI button. Freeze one feature, switch LIVE OFF, and verify that frozen panel remains visible while ordinary panels hide; switch LIVE ON and unfreeze. Confirm initial eye zoom reads 0.50× and smoothing reads 0.
7. Sweep the pointer across the feature panels and verify scale, crop zoom, and frames do not change. Repeat in another Space and alongside a full-screen app.
8. Repeat placement/crop checks on a Retina display and with an external display connected, including a display with a negative desktop origin.
9. Quit with the menu action and with Ctrl-C in separate runs. After each, verify the shell has normal echo/canonical input, the cursor is visible, and the original screen is restored.
10. Run LIVE for at least ten minutes. Record Activity Monitor memory at start (after one-minute warm-up), peak, and each minute through the end; record observed camera-to-panel latency and whether memory plateaus. Save an Instruments/Activity Monitor artifact with the notes.

Current TTY repro from the available runner:

```sh
./blobby-cam
```

The previous signed build had `com.apple.security.app-sandbox=true`; both Debug and Release also set `ENABLE_APP_SANDBOX=YES`. That sandboxed app logged `tcsetattr raw mode: Operation not permitted` and fell back to the GUI. The current build disables App Sandbox and retains the camera-only entitlement plus `NSCameraUsageDescription`. A focused Xcode test-host process emitted the 80×24 menu in its PTY without that EPERM. A separate direct exec in this runner terminated with Swift Signal 6 immediately after `Blobby Cam lifecycle: explicit application bootstrap`, before `AppDelegate` or `TerminalSession` started; this runner-only startup failure is distinct from the old raw-mode denial. The user must verify startup and cleanup in real Terminal.app.

The raw-mode boundary was isolated with a shell `stty raw`/restore control and a minimal C `tcgetattr → tcsetattr raw → tcsetattr restore` probe signed with the current camera-only entitlement; both passed in the available PTY. This confirms the raw-mode syscall works when the process is not App Sandbox restricted. Camera privacy consent continues to use `NSCameraUsageDescription` and macOS TCC. The local Developer ID distribution target remains unsandboxed; a Mac App Store sandbox target is outside this TUI v0 architecture.

T18 runtime follow-up: Terminal input now has a production-PTY integration test that sends Down, Enter, Up, and Enter through `DarwinTerminalSessionIO`, verifies menu selection and shared `AppState` updates, and checks termios restoration. TTY and Finder/non-TTY startup now default LIVE on. Before the app creates `NSApplication`, it retains the previously frontmost app; after camera authorization resolves or fails, the TTY path yields activation back to that app so Terminal keeps the keyboard. The focus transfer and automatic first camera prompt still need a real Terminal.app check.

## Memory and latency record

| Measurement | Result |
|---|---|
| Warm-up memory | Not measured — live camera run blocked |
| Peak memory | Not measured — live camera run blocked |
| End memory after ≥10 minutes | Not measured — live camera run blocked |
| Plateau observed | Not established |
| Camera-to-panel latency | Not measured |
