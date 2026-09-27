# BLOBBY_CAM_BUILD_PLAN.md

## 1. BUILD TARGET

- Native Swift macOS 14+ webcam app; one capture session and one current `CVPixelBuffer` path.
- Apple Vision tracks `LEFT EYE`, `RIGHT EYE`, `NOSE`, `MOUTH`, `LEFT HAND`, `RIGHT HAND`.
- Each feature has one persistent, independent, real, floating `NSPanel` displaying a live crop.
- The primary control surface is an ASCII Terminal menu launched with one local command; arrow keys navigate and change live state, visibility, follow, smoothing, mirror, reset, and each feature's settings.
- `SHOW GOOFY UI` at the bottom of the Terminal menu opens the existing fixed-size Blobby Menu as an optional secondary view of the same `AppState`.
- **DONE:** the Section 9 acceptance matrix passes, the ten-minute memory run plateaus, and a local macOS app build launches.
- **Outside v0:** uploaded video, recording/export, timeline, delay, echoes/trails, hair segmentation, arbitrary objects, cloud/accounts, mobile UI, effect carousel, node editor, and a final logo.
- No React, Vite, JavaScript, WebView, Electron, Tauri, browser MediaPipe, FFmpeg, or unprofiled custom Metal shader engine.

**Product revisions, 2026-09-26:** Feature windows use real AppKit Terminal-like titled chrome with a solid dark titlebar; live crops fill their content areas. All six persist without overlap. Selfie mirror is the default for pixels and placement. Native edge-drag resize persists in shared state. The latest user decision makes the Terminal ASCII menu primary; the existing fixed-size Blobby Menu is optional behind `SHOW GOOFY UI`. Brand ASCII art will be supplied later, so reserve a compact placeholder. Window geometry and crop zoom/pan remain independent. The one-camera, Vision, and shared CI/Metal architecture stays frozen.

`OPEN_QUESTION — SOURCE`: The research file now in the repo is `fun-tracking.md`. It is a detailed research handoff containing a link to `blobby-cam-native-macos-research.md`, but that linked file is not present. This plan uses `fun-tracking.md` and the user's project contract. Agents can execute the specified tasks from these inputs. If the full linked document is supplied later and conflicts with this plan, stop at the affected task and reconcile that specific conflict; do not silently choose a new architecture.

## 2. ARCHITECTURE FREEZE

| DECISION | WHY | DO NOT SUBSTITUTE WITH |
|---|---|---|
| Native macOS 14+ Swift app: AppKit windows, SwiftUI only inside the control menu | Research's product and deployment target | Web runtime, cross-platform shell, six SwiftUI scene windows |
| One `AVCaptureSession` → `AVCaptureVideoDataOutput` → `CVPixelBuffer` | Shared webcam source and low-copy pipeline | Six capture sessions, still-image capture, encoded frame loop |
| Serial video callback, `alwaysDiscardsLateVideoFrames = true`; short callback, separate serial Vision work | Bounded real-time backlog | Unbounded per-frame tasks or queues |
| `VNSequenceRequestHandler`, `VNDetectFaceLandmarksRequest`, `VNDetectHumanHandPoseRequest(maximumHandCount: 2)` | Native face regions and semantic hand pose | MediaPipe, custom ML model, screen-position hand identity |
| Face landmark regions mapped through face `boundingBox`; hand `chirality` and joint confidence | Correct geometry and semantics | Invented face-point confidence or left/right by horizontal order |
| One latest-frame store, no frame history in v0 | Live-only scope and bounded memory | Frame ring, six full pixel-buffer copies |
| Shared `CIContext(MTLDevice)` and `CIImage(cvPixelBuffer:)` crop path; six small Metal-backed views | Research's first rendering strategy | Per-frame JPEG/PNG/`NSImage`, six CI contexts, custom shaders before profiling |
| Six persistent titled, nonactivating floating `NSPanel` instances with native Terminal-like dark chrome; show/hide/move/resize | User's visual review and the core real-window mechanic | Fake painted titlebars, transparent floating labels, one compositor canvas, per-frame window creation |
| Feature panels join Spaces and are full-screen auxiliary by default | Research's overlay behavior | Normal activating document windows |
| One Terminal ASCII control surface launched from the project with `./blobby-cam`; arrow keys navigate; AppKit continues to own the six real panels | User's latest control-surface decision | A second camera process, browser TUI, global keyboard interception |
| Existing fixed-size Blobby Menu is optional through `SHOW GOOFY UI`; both surfaces share `AppState` | Keep the completed GUI as an optional feature | Auto-opening GUI in Terminal mode, duplicate state, extra settings windows |
| Feature windows support native edge-drag resize, with size readout/reset in controls; crop zoom/pan change framing independently | User's direct-manipulation preference | Hover resize, pointer magnification, per-frame size reset |
| Selfie mirror on by default and applied once to crop pixels and panel placement; six panels never intersect | Live visual acceptance | Double mirroring, left/right labels based only on screen position, overlapping panels |
| Map Vision eye regions once to the selfie-facing `FeatureID` labels verified in live preview; `LEFT EYE` must be the displayed left eye | User's 2026-09-26 screenshot showed otherwise-correct eye windows with reversed titles | Swapping title strings while leaving per-eye controls attached to the wrong crop |
| Confidence lifecycle `HIDDEN → VISIBLE → GRACE → HIDDEN`, with smoothing | Prevent tracking flicker | Immediate hide on one missed detection |
| Default tuning: show 0.55, hold 0.40, grace 250 ms, hide fade 120 ms, EMA 0.30, crop padding 25%, window scale 0.25–4× | Research's starting values, subject to measured tuning | Treating these values as Apple API guarantees |
| Zero runtime SPM dependencies; AppKit, SwiftUI, AVFoundation, Vision, CoreVideo, CoreImage, Metal, MetalKit, QuartzCore | Minimal native stack | Third-party runtime dependency without task-specific necessity |
| Unsandboxed local Terminal-first app with camera entitlement and `NSCameraUsageDescription`; macOS TCC controls camera consent; local release uses Developer ID, Hardened Runtime, notarization when credentials exist | Raw-mode `tcsetattr` on the controlling TTY is denied by App Sandbox; direct local distribution preserves the same app process and camera privacy prompt | Re-enabling App Sandbox for the Terminal-first v0 target |

## 3. MODULE MAP

| MODULE | PURPOSE | OWNS | MUST NOT OWN | PUBLIC INTERFACE / DATA IT EXPOSES | DEPENDENCIES |
|---|---|---|---|---|---|
| `App/` | Lifecycle and shared configuration | `AppState`, `FeatureID`, `FeatureConfiguration`, app assembly | Pixel processing, panel drawing | `AppState` snapshots/actions, `FeatureID` | Foundation, AppKit; consumes other modules |
| `Camera/` | Permission, one capture session, latest frame | `CameraFrame`, `LatestFrameStore`, capture lifecycle | Vision results, windows, UI | permission status, start/stop, `CameraFrame` delivery, latest frame | AVFoundation, CoreVideo, App contracts |
| `Vision/` | Face/hand requests, region extraction, confidence lifecycle | `FeatureDetection`, `TrackingSnapshot`, `TrackingSmoother`, `WindowLifecycleState` | Camera session, panels, UI controls | `process(CameraFrame) -> TrackingSnapshot`, smoothed states | Vision, Camera, App contracts |
| `Windows/` | Six panels and screen coordinates | `FeaturePanel`, `FeatureWindowManager`, `ScreenMapper` | Vision requests, capture, duplicate config state | `apply(snapshot:frame:configuration:)`, show/hide | AppKit, App/Vision/Rendering contracts |
| `Rendering/` | Shared CI/Metal crop display | one renderer/context, per-panel render view | Camera ownership, tracking decisions, window policy | `render(frame:crop:in:)` using source-pixel rect | CoreImage, Metal, MetalKit, CoreVideo |
| `Terminal/` | Primary ASCII menu, arrow navigation, terminal lifecycle | key parser, menu model/renderer, raw-mode session | camera session, Vision, panel rendering, global key interception | typed menu actions and terminal events | Foundation/Darwin, App contracts |
| `Menu/` | Optional fixed-size Goofy UI | `BlobbyMenuView`, rows, theme | Camera/Vision implementation, extra windows | bound controls emitting `AppState` actions | SwiftUI, App contracts |
| `Resources/` | Assets, camera entitlement, usage text | `Assets.xcassets`, `BlobbyCam.entitlements` | Runtime logic | bundled configuration | Xcode project |
| `BlobbyCamTests/` | Focused pure-contract and geometry/lifecycle tests | test fixtures | alternate architecture | XCTest results | Tested modules |

`App/` is the single owner of feature configuration; `Vision/` owns detections; `Windows/` owns panel state. No module keeps a second mutable copy of these models.

## 4. CORE DATA CONTRACTS

These are interface sketches, not implementations. T01 creates canonical declarations once; later agents import them. `CGRect` for tracking and crop is **normalized full-image coordinates** until `ScreenMapper` converts to source pixels and AppKit screen points. Document camera orientation and mirror transform in that mapper; apply each transform exactly once. Timestamps use `CMTime` from the captured sample. A `nil` detection means missing or invalid geometry, never a fabricated zero-confidence landmark.

```swift
// App/FeatureID.swift
enum FeatureID: String, CaseIterable, Codable {
    case leftEye, rightEye, nose, mouth, leftHand, rightHand
}

// App/FeatureConfiguration.swift
struct FeatureConfiguration: Equatable {
    var isEnabled: Bool
    var windowScale: CGFloat       // clamped to 0.25...4
    var windowSizeOverride: CGSize? // native edge-drag size; nil uses windowScale
    var cropPadding: CGFloat       // fraction of detected bounds; default 0.25
    var cropZoom: CGFloat          // source framing, independent of windowScale
    var cropOffsetX: CGFloat       // pan within source image, normalized to region
    var cropOffsetY: CGFloat
    var windowOffsetX: CGFloat     // screen-point displacement before collision resolution
    var windowOffsetY: CGFloat
    var detectionThreshold: Float  // region eligibility, not face-landmark confidence
}

// Camera/CameraFrame.swift
struct CameraFrame {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let orientation: CGImagePropertyOrientation
    let isMirrored: Bool           // capture/display policy, interpreted once
}

// Camera/LatestFrameStore.swift
protocol LatestFrameStore {
    func replace(with frame: CameraFrame)
    func latest() -> CameraFrame?
}

// Vision/TrackingSnapshot.swift
struct FeatureDetection {
    let id: FeatureID
    let normalizedRect: CGRect     // full-image, before crop padding
    let confidence: Float          // face observation or hand-joint aggregate
    let timestamp: CMTime
}
struct TrackingSnapshot {
    let timestamp: CMTime
    let detections: [FeatureID: FeatureDetection]
}

// Vision/WindowLifecycleState.swift
enum WindowLifecycleState {
    case hidden
    case visible
    case grace(lastSeen: CMTime)
}

// App/AppState.swift
@MainActor final class AppState: ObservableObject {
    @Published private(set) var isLive: Bool
    @Published private(set) var showAll: Bool
    @Published private(set) var follow: Bool
    @Published private(set) var smoothing: CGFloat
    @Published private(set) var mirror: Bool // selfie default true
    @Published private(set) var features: [FeatureID: FeatureConfiguration]
    // Actions: setLive, setShowAll, setFollow, setSmoothing,
    // setMirror, setFeatureEnabled, setWindowScale, setWindowOffsetX/Y,
    // setCropPadding, setCropZoom, setCropOffsetX/Y,
    // setDetectionThreshold, reset.
}
```

Terminal contracts added after the control-surface revision (owned only by `Terminal/`):

```swift
enum TerminalKey: Equatable { case up, down, left, right, enter, escape, quit }
enum TerminalFeatureField: CaseIterable, Equatable { case enabled, sizeReset, windowX, windowY, cropZoom, panX, panY, padding, detection }
enum TerminalMenuAction: Equatable {
    case toggleLive, toggleAll, toggleFollow, toggleMirror, resetAll
    case adjustSmoothing(Int)
    case toggleFeature(FeatureID)
    case resetFeatureSize(FeatureID)
    case adjustFeature(FeatureID, TerminalFeatureField, Int)
    case toggleGoofyUI, quit
}
// Terminal menu state owns selection/navigation only; AppState remains the sole value owner.
```

`OPEN_QUESTION — ASCII ART`: The user will supply branded ASCII art later. Reserve a compact text placeholder only; do not invent the final mark.

`OPEN_QUESTION — PUBLIC INSTALL`: A signed/hosted one-line public installer needs release credentials and a distribution URL. Until then, the reproducible local one-line command is `./blobby-cam` from this project folder; do not modify files outside it.

`OPEN_QUESTION — FOLLOW`: The handoff names `FOLLOW` but does not define its disabled behavior. Until the full research resolves it, use the minimal interpretation: when off, keep the last panel position while continuing live crop and detection lifecycle; when on, move panels with smoothed feature position. Do not add motion modes.

`OPEN_QUESTION — CONFIDENCE`: Face detection threshold uses face observation confidence plus geometry validity, because Vision does not give each face landmark its own confidence. Hand threshold uses a documented aggregate of required joint confidences. T06 must record the exact aggregate and missing-joint policy before implementation; no invented per-landmark score.

## 5. TASK GRAPH

### T00 — Native project scaffold

GOAL: Build and launch an empty native macOS app.

DEPENDS ON: none.

FILES / MODULES: `BlobbyCam.xcodeproj/`, `BlobbyCam/App/AppDelegate.swift`, `BlobbyCam/Resources/Assets.xcassets/`, `BlobbyCam/Resources/BlobbyCam.entitlements`, `BlobbyCam/Info.plist`, `BlobbyCamTests/`.

IMPLEMENT:
- Create a macOS 14+ Swift app target and XCTest target; use AppKit lifecycle with a placeholder single menu window.
- Add camera usage description and camera-only entitlement. Keep App Sandbox disabled for the Terminal-first executable so its controlling TTY can enter raw mode. Link only the listed Apple frameworks.
- Keep the repo's research document as agent input; do not copy research prose into app files.

DO NOT: Add capture, tracking, six panels, package dependencies, logo, or extra windows.

OUTPUT: Xcode project, launchable app, test target.

VERIFY: `xcodebuild -list -project BlobbyCam.xcodeproj`; build the app and test targets for macOS; launch and observe one placeholder window.

DONE WHEN: Both targets build; app launches with exactly one placeholder window; deployment target is 14+; usage text and camera entitlement exist.

NEXT: T01.

### T01 — Shared contracts and state

GOAL: Establish one compile-checked source for shared types and defaults.

DEPENDS ON: T00.

FILES / MODULES: `BlobbyCam/App/FeatureID.swift`, `FeatureConfiguration.swift`, `AppState.swift`; `BlobbyCam/Camera/CameraFrame.swift`, `LatestFrameStore.swift`; `BlobbyCam/Vision/TrackingSnapshot.swift`, `WindowLifecycleState.swift`; `BlobbyCamTests/ContractTests.swift`.

IMPLEMENT:
- Create Section 4 types/actions and six default configurations; clamp scale and thresholds at state action boundaries.
- Keep `AppState` main-actor isolated and expose changes through actions.
- Define coordinate and timestamp comments exactly once at type declarations.

DO NOT: Build camera, Vision, windows, or menu controls; add duplicate model types.

OUTPUT: Compiling shared contracts and default-state tests.

VERIFY: Build and run `ContractTests`; inspect that every `FeatureID` has one config.

DONE WHEN: Six IDs and configs exist; defaults match Section 2; invalid scale/threshold input is clamped; tests pass.

NEXT: T02, T09, T10, T14.

### T02 — Camera permission

GOAL: Resolve allow and deny states without starting capture prematurely.

DEPENDS ON: T01.

FILES / MODULES: `BlobbyCam/Camera/CameraPermission.swift`, `BlobbyCamTests/CameraPermissionTests.swift`.

IMPLEMENT:
- Wrap AVFoundation video authorization status and request-once flow.
- Report authorized, denied/restricted, and not-determined outcomes to caller.
- Surface denied/restricted status in the primary Terminal menu through state; the optional Goofy UI may mirror it. Expose no new permission window.

DO NOT: Start a session or assume access after denial.

OUTPUT: Permission service callable by T03/T18.

VERIFY: Unit-test status mapping; manually check allow and deny on a clean permission state or documented reset.

DONE WHEN: Allow permits later capture; deny yields a stable noncapturing state; app remains responsive.

NEXT: T03.

### T03 — Single camera capture

GOAL: Deliver timestamped raw camera frames from one session.

DEPENDS ON: T01, T02.

FILES / MODULES: `BlobbyCam/Camera/CameraCapture.swift`, `BlobbyCam/Camera/CameraFrame.swift` (interface-preserving additions only), `BlobbyCamTests/CameraCaptureTests.swift`.

IMPLEMENT:
- Configure one device input and one `AVCaptureVideoDataOutput`; set `alwaysDiscardsLateVideoFrames = true` and a serial delegate queue.
- Extract `CVPixelBuffer`, timestamp, and orientation/mirror metadata; send frames to one callback.
- Provide idempotent start/stop and reconnect after device interruption/return; publish errors without crashing.
- Keep sample-buffer callback short; never block main thread.

DO NOT: Create Vision requests, CI rendering, image encodes, another capture pipeline, or per-frame unbounded tasks.

OUTPUT: Camera service with observable start/stop/error behavior.

VERIFY: Build; manual start/stop/reconnect and denied access; inspect capture graph at runtime.

DONE WHEN: Authorized webcam emits increasing timestamps; stop stops delivery; restart resumes; exactly one session/output exists.

NEXT: T04.

### T04 — Bounded latest-frame store

GOAL: Retain at most the newest frame for downstream work.

DEPENDS ON: T01, T03.

FILES / MODULES: `BlobbyCam/Camera/LatestFrameStore.swift`, `BlobbyCamTests/LatestFrameStoreTests.swift`.

IMPLEMENT:
- Make replacement and retrieval thread-safe, with clear pixel-buffer lifetime.
- Replace old frames rather than enqueue a history; expose latest timestamp.
- Add a narrow test for replacement and concurrent read/write safety.

DO NOT: Add frame ring, disk cache, six copies, or image conversion.

OUTPUT: Store wired to capture callback.

VERIFY: Run store tests; observe bounded retained-frame count during live capture.

DONE WHEN: Latest wins, old buffers release, and memory does not grow with frame count in this subsystem.

NEXT: T05, T06, T12.

### T05 — Face landmark regions

GOAL: Extract four valid normalized face regions from one Vision face observation.

DEPENDS ON: T01, T04.

FILES / MODULES: `BlobbyCam/Vision/FaceRegionExtractor.swift`, `BlobbyCamTests/FaceRegionExtractorTests.swift`.

IMPLEMENT:
- Use face-landmark output for left/right eyes, nose, and mouth (`outerLips` with documented fallback if source supports it).
- Normalize Vision eye region names to the selfie-facing `FeatureID` labels once here; the live reference requires `LEFT EYE` on the displayed left and `RIGHT EYE` on the displayed right.
- Convert points from face-bounding-box coordinates into full-image normalized rectangles.
- Reject absent or degenerate regions; use face observation confidence, never fictional region-point confidence.

DO NOT: Decide mirror display policy, create windows, or perform camera capture.

OUTPUT: Four `FeatureDetection` candidates for a face observation.

VERIFY: Pure geometry tests including off-center face; live preview diagnostic values for all four features.

DONE WHEN: Four regions are in full-image normalized bounds on a detectable face; missing landmark yields no detection.

NEXT: T07.

### T06 — Hand pose regions and semantic IDs

GOAL: Extract up to two hand rectangles with chirality-based feature IDs.

DEPENDS ON: T01, T04.

FILES / MODULES: `BlobbyCam/Vision/HandRegionExtractor.swift`, `BlobbyCamTests/HandRegionExtractorTests.swift`.

IMPLEMENT:
- Use `VNHumanHandPoseObservation` recognized joints and `chirality`.
- Derive a bounded rectangle from valid joints; document which joints are required and the confidence aggregation.
- Omit unidentified/invalid hands rather than guessing identity from screen position.

DO NOT: Swap semantic labels to match a mirrored preview; add body pose or custom hand model.

OUTPUT: Zero to two `FeatureDetection` candidates keyed by left/right hand.

VERIFY: Geometry and chirality tests; manual test with either hand and both hands.

DONE WHEN: Semantic IDs follow Vision chirality when hands cross or mirror toggles; missing joints cannot yield an invalid rect.

NEXT: T07.

### T07 — Vision request coordinator

GOAL: Produce one coherent tracking snapshot per analyzed frame.

DEPENDS ON: T05, T06.

FILES / MODULES: `BlobbyCam/Vision/VisionTracker.swift`, `BlobbyCamTests/VisionTrackerTests.swift`.

IMPLEMENT:
- Own one serial analysis queue and `VNSequenceRequestHandler`; run face landmarks and hand pose requests, with maximum hand count 2.
- Consume the newest frame only when ready, dropping obsolete analysis opportunities.
- Stamp all detections with the source frame time; publish one immutable snapshot.
- Record orientation policy; use frame metadata once, with T11 as the visual mapping authority.

DO NOT: Block the capture callback, retain a frame history, display windows, or invent face landmark confidence.

OUTPUT: `process/latest` tracking service delivering six possible IDs.

VERIFY: Build; live diagnostic log/snapshot for face and two hands; confirm timestamps never go backward.

DONE WHEN: Both requests run from the same camera source; no growing analysis queue; snapshots contain valid supported IDs only.

NEXT: T08.

### T08 — Region geometry and crop policy

GOAL: Convert normalized detections into safe padded source crop rectangles.

DEPENDS ON: T07.

FILES / MODULES: `BlobbyCam/Vision/FeatureGeometry.swift`, `BlobbyCamTests/FeatureGeometryTests.swift`.

IMPLEMENT:
- Expand each region by its per-feature crop padding; clamp to image bounds and preserve nonzero dimensions.
- Use the hand confidence aggregate and absent-joint policy established in T06; do not redefine them here.
- Keep orientation/mirror application outside this pure crop calculation.

DO NOT: Allocate cropped pixel buffers or move windows.

OUTPUT: Deterministic normalized crop rect API.

VERIFY: Tests for edges, tiny features, padding extremes, and image-bound clamping.

DONE WHEN: Every accepted detection gives a finite in-bounds crop; invalid detection gives no crop.

NEXT: T12, T13.

### T09 — Smoothing and detection lifecycle

GOAL: Stabilize coordinates and visibility using confidence hysteresis.

DEPENDS ON: T01.

FILES / MODULES: `BlobbyCam/Vision/TrackingSmoother.swift`, `BlobbyCamTests/TrackingSmootherTests.swift`.

IMPLEMENT:
- Implement EMA default 0.30 on valid feature geometry and per-feature show/hold threshold logic.
- Hold last good geometry for 250 ms after a miss; transition to hidden after grace, with 120 ms hide fade signal.
- Reset stale state on camera stop, feature off, and reset; use frame timestamps rather than wall-clock arrival for ordering.

DO NOT: Treat missing landmarks as zero-position detections or create panels.

OUTPUT: Stable per-feature detection and lifecycle result consumed by T13.

VERIFY: Deterministic tests for show, one-frame miss, reacquisition, timeout, stale timestamp, and reset.

DONE WHEN: Single-frame misses do not hide a visible feature; sustained misses do; no position jumps to origin.

NEXT: T13.

### T10 — Persistent native feature panels

GOAL: Own exactly six real reusable feature windows.

DEPENDS ON: T01.

FILES / MODULES: `BlobbyCam/Windows/FeaturePanel.swift`, `BlobbyCam/Windows/FeatureWindowManager.swift`, `BlobbyCamTests/FeatureWindowManagerTests.swift`.

IMPLEMENT:
- Construct one `NSPanel` per `FeatureID` using real titled/nonactivating AppKit style, solid dark Terminal-like titlebar/content background, floating level, `hidesOnDeactivate = false`, `canJoinAllSpaces`, and `fullScreenAuxiliary`.
- Expose show/hide/move/programmatic-size operations plus native edge-drag resize. Publish a completed user resize through a callback for T13 to store in shared feature configuration; keep panel identity stable for process lifetime.
- Make panel content accept a render view via a narrow interface; keep pointer hover inert.

DO NOT: Draw six features in one canvas, recreate panels per frame, reset a manually dragged size on the next video frame, resize on pointer hover, or activate keyboard focus.

OUTPUT: Six panel objects even while hidden.

VERIFY: Unit-test stable object identities; manual native titlebar, focus/Spaces/full-screen check with blank panel contents.

DONE WHEN: Exactly six distinct `NSPanel` instances persist across repeated show/hide cycles, allow native edge-drag resize, and do not steal focus.

NEXT: T11, T12.

### T11 — Camera-to-screen mapping

GOAL: Place feature panels correctly on Retina and external displays.

DEPENDS ON: T10.

FILES / MODULES: `BlobbyCam/Windows/ScreenMapper.swift`, `BlobbyCamTests/ScreenMapperTests.swift`.

IMPLEMENT:
- Centralize source orientation, selfie mirror default, normalized-to-pixel, and AppKit screen-point transformations.
- Derive panel position from smoothed detection center, per-feature window offset, available screen frame, and panel size; clamp visible placement.
- Resolve collisions deterministically: eyes above, nose centered below, mouth centered below nose; place hands separately. Never overlap panels or the menu.
- Handle multiple displays and backing scale without applying mirror twice; document selected display policy.

DO NOT: Change semantic hand IDs or use raw Vision coordinates directly as `NSWindow` frame points.

OUTPUT: Tested pure mapping API used by T13.

VERIFY: Fixture tests for mirrored/unmirrored, portrait-like orientation, Retina scale, negative external-screen origins; manual two-display check.

DONE WHEN: All six features visually align with their source regions on primary and external displays; selfie mirror is correct by default and toggles once; panels do not overlap.

NEXT: T13.

### T12 — Shared live crop renderer

GOAL: Draw six live crops from one shared frame without per-frame image encoding.

DEPENDS ON: T04, T08, T10.

FILES / MODULES: `BlobbyCam/Rendering/SharedRenderer.swift`, `CoreImageCropRenderer.swift`, `BlobbyCam/Windows/FeatureRenderView.swift`, `BlobbyCamTests/RendererGeometryTests.swift`.

IMPLEMENT:
- Create one shared `CIContext` backed by one `MTLDevice`; source `CIImage` directly from `CVPixelBuffer`.
- Render each feature's padded/zoomed/panned live source crop with aspect-fill into 100% of its panel content area; manage frame lifetime until GPU work completes.
- Apply bounds/orientation consistently with T11; skip invalid crops and stale frames.

DO NOT: Implement `MetalCropRenderer.swift` or custom shaders before profiling; allocate six full buffers or convert frames to JPEG/PNG/`NSImage`.

OUTPUT: Six independently displayable live crop views with one shared renderer.

VERIFY: Live visual crop check; inspect allocations and code path for image conversions; measure display latency.

DONE WHEN: All views show distinct live crops from the same frame without black letterboxing; no forbidden per-frame conversion or full-frame copy exists.

NEXT: T13.

### T13 — Tracking-to-window integration

GOAL: Drive persistent panels from live tracking and rendering.

DEPENDS ON: T08, T09, T11, T12.

FILES / MODULES: `BlobbyCam/App/AppDelegate.swift`, `BlobbyCam/App/AppState.swift`, `BlobbyCam/App/FeatureConfiguration.swift`, `BlobbyCam/Windows/FeatureWindowManager.swift`, `BlobbyCam/Vision/VisionTracker.swift` (wiring only), `BlobbyCamTests/IntegrationStateTests.swift`.

IMPLEMENT:
- Consume coherent latest frame/snapshot, smooth positions, map to screen, render, and show/hide the existing panels on main actor.
- Respect feature enabled, global show/hide, follow, and live state. Store completed native resize in the corresponding feature configuration; do not fight AppKit during a drag or reset size on later frames. Keep each crop centered within its window while live pixels update.
- Prevent out-of-order snapshots from moving a panel backward; cleanly stop on camera interruption.

DO NOT: Add menu styling, recreate panels, add extra capture, or alter shared contracts casually.

OUTPUT: Working camera-to-six-window vertical slice.

VERIFY: Runtime two-hands/face check, toggle state programmatically, focus check, no per-frame panel allocation check.

DONE WHEN: Six live native Terminal-like windows follow supported features without overlap; crops fill the content area; native drag size persists; selfie mirror is correct; brief misses hold; disabling a feature hides only its panel.

NEXT: T15, T16.

### T14 — Optional Goofy UI design system and fixed shell

GOAL: Establish the optional fixed-size Blobby Menu shell.

DEPENDS ON: T01.

FILES / MODULES: `BlobbyCam/Menu/BlobbyTheme.swift`, `BlobbyCam/Menu/BlobbyMenuView.swift`, `BlobbyCam/App/AppDelegate.swift` (menu window construction only).

IMPLEMENT:
- Apply paper `#F4F2EA`, ink `#111113`, base `#7A17E0`, base-deep `#4E0FA0`, accent `#FF70B8`, accent-soft `#FFA6D3`.
- Use clean layout, 2 pt ink borders, about 16 pt radius, hard offset shadows, uppercase short labels, and a small empty logo placement.
- Create one nonresizable menu window with fixed min/max/content size; support vertical content within that fixed shell.

DO NOT: Add tilt, gradients, glass, blur, final logo, hover scale, extra settings window, or camera controls yet.

OUTPUT: Static menu shell and theme.

VERIFY: Build; visual inspection; attempt user resize and pointer hover.

DONE WHEN: At most one Goofy UI window exists when shown, resizing is impossible, and no window scales or animates on hover.

NEXT: T15.

### T15 — Optional Goofy UI controls

GOAL: Expose every v0 control in the optional fixed menu.

DEPENDS ON: T13, T14.

FILES / MODULES: `BlobbyCam/Menu/BlobbyMenuView.swift`, `FeatureControlRow.swift`, `BlobbyCam/Menu/BlobbyTheme.swift` (small corrections only).

IMPLEMENT:
- Add LIVE, SHOW/HIDE ALL, FOLLOW, SMOOTHING, MIRROR, RESET, and six per-feature ON/OFF, native WINDOW SIZE readout/reset, WINDOW X/Y, CROP ZOOM, CROP X/Y, CROP/PADDING, DETECTION controls. Window geometry and crop framing are independent.
- Keep rows compact: native edge drag is the primary sizing gesture; group crop pan into one two-axis control or compact editor, and put less-used numeric controls in a disclosure area instead of showing ten sliders per feature.
- Bind controls only to `AppState` actions; label face DETECTION honestly as observation/geometry threshold, not landmark confidence.
- Keep usable hit targets and scroll content inside the fixed window if needed.

DO NOT: Add global controls absent from research, another window, hover magnification, or unbounded sliders.

OUTPUT: Complete optional Goofy UI control view, sharing `AppState` with the future Terminal primary menu.

VERIFY: Manual keyboard/pointer pass through every control and six rows; window bounds stay fixed.

DONE WHEN: Every listed action changes state; all controls remain reachable; pointer hover changes neither menu nor feature-window size.

NEXT: T16, T18.

### T16 — Terminal menu model and ASCII renderer

GOAL: Produce a compact, deterministic Terminal menu and typed actions without terminal I/O.

DEPENDS ON: T01, T15.

FILES / MODULES: `BlobbyCam/Terminal/TerminalMenuModel.swift`, `BlobbyCam/Terminal/TerminalMenuRenderer.swift`, `BlobbyCamTests/TerminalMenuTests.swift`, `BlobbyCam.xcodeproj/project.pbxproj` (registration only).

IMPLEMENT:
- Own `TerminalKey`, `TerminalFeatureField`, `TerminalMenuAction`, navigation selection, and action emission in `Terminal/` only. Up/Down selects; Left/Right adjusts; Enter toggles or enters a feature; Escape returns to the top level.
- Show global LIVE, SHOW/HIDE ALL, FOLLOW, MIRROR, SMOOTHING, RESET, six feature entries, and bottom `SHOW GOOFY UI`/`HIDE GOOFY UI` plus QUIT. Feature details expose ON/OFF, window-size readout/reset, X/Y placement, crop zoom, pan X/Y, padding, and detection.
- Render plain ASCII text sized for an 80×24 terminal. Reserve a compact placeholder for the later user-supplied brand art. Read values from a snapshot of `AppState`; do not duplicate them.
- Render the selected row in pink (`#FF70B8`, with an ANSI terminal-color fallback) and mark it with `>`. An active toggle remains pink after selection moves to another row; selection and active state must be independently visible.

DO NOT: Open an AppKit window, read stdin, change camera/renderer code, invent final ASCII art, or add a dependency.

OUTPUT: Pure, testable menu state machine and ASCII frame string.

VERIFY: Unit tests for navigation, every emitted action, selection bounds, all six features, selected/active pink styling, and an 80-column/24-line render measured after stripping ANSI sequences.

DONE WHEN: Every control has one reachable keyboard path and the rendered frame is legible within 80×24 without live terminal access.

NEXT: T17.

### T17 — Terminal session and key input

GOAL: Read arrow keys reliably and redraw the ASCII menu while preserving the user's Terminal state.

DEPENDS ON: T16.

FILES / MODULES: `BlobbyCam/Terminal/TerminalKeyParser.swift`, `BlobbyCam/Terminal/TerminalSession.swift`, `BlobbyCamTests/TerminalKeyParserTests.swift`, `BlobbyCam.xcodeproj/project.pbxproj` (registration only).

IMPLEMENT:
- Require an attached TTY in primary mode. Use Darwin `termios` to read keys without line buffering/echo, parse escape sequences incrementally, and send typed `TerminalKey` events; never intercept keys globally.
- Draw via ANSI cursor positioning/alternate screen or an equivalent terminal-only method; restore the original terminal mode, cursor, and screen on normal quit and handled Ctrl-C/error. Keep AppKit on the main actor and terminal input off the main thread.
- Make input/output injectable so parsing and cleanup can be tested without controlling the user's Terminal.

DO NOT: Start camera capture, create GUI windows, use a shell UI framework, or swallow unrelated application keystrokes.

OUTPUT: Reusable terminal session with deterministic start/stop and key delivery.

VERIFY: Parser tests for arrows/Enter/Escape/Ctrl-C and incomplete sequences; session lifecycle test with injected streams; build.

DONE WHEN: One TTY session starts, handles keys, redraws, and restores terminal settings on every supported exit path.

NEXT: T18.

### T18 — Terminal-first app integration and local command

GOAL: Run one native camera app with Terminal controls by default and optional Goofy UI.

DEPENDS ON: T13, T15, T16, T17.

FILES / MODULES: `BlobbyCam/App/AppDelegate.swift`, `BlobbyCam/App/AppState.swift` (only needed state/status), `BlobbyCam/Terminal/TerminalMenuController.swift`, `BlobbyCamTests/ControlIntegrationTests.swift`, `BlobbyCam.xcodeproj/project.pbxproj` (registration only), `blobby-cam` (local launcher).

IMPLEMENT:
- Launch the `.app` executable from Terminal through `./blobby-cam` in this folder; start the Terminal menu and the existing single-process AppKit/camera pipeline. Keep Terminal focused while six nonactivating feature panels work. Do not create/show the Goofy UI on a TTY launch.
- Dispatch every `TerminalMenuAction` to the existing `AppState` action. LIVE controls camera permission/start/stop; show denial/interruption/error in ASCII; RESET clears defaults and stale tracking. Preserve native edge-drag size and independent crop framing.
- `SHOW GOOFY UI` creates/shows the existing fixed-size menu lazily; `HIDE GOOFY UI` hides it without exiting. Both surfaces share the same state. Finder launch without a TTY may show the Goofy UI as a usable fallback, documented as such.
- Keep only one camera session and six persistent panels. Closing optional UI must not terminate an active Terminal session.

DO NOT: Spawn a separate GUI/camera process, add IPC/backend, auto-open Goofy UI in TTY mode, change Vision/CI architecture, or install outside this project folder.

OUTPUT: Working `./blobby-cam` local one-line launch with arrow-key ASCII control and optional Goofy UI.

VERIFY: Run command in Terminal; allow/deny camera; navigate/adjust/toggle all controls; show/hide Goofy UI; quit and confirm Terminal restoration; run integration tests.

DONE WHEN: Terminal is the default control surface from the local command; six native windows respond live; optional GUI is absent until requested; no duplicate capture process exists.

NEXT: T19.

### T19 — Stability and acceptance QA

GOAL: Close all Section 9 runtime and performance gates for Terminal-first v0.

DEPENDS ON: T18.

FILES / MODULES: `BlobbyCamTests/`, existing affected source files only, `QA_NOTES.md` for reproducible evidence.

IMPLEMENT:
- Run matrix on a real Mac webcam, two hands, Spaces/full-screen, Retina, external display, camera interruption, denied permission, terminal arrow controls, optional GUI, and TTY cleanup.
- Run at least ten minutes; record memory start, peak, end/plateau and observed frame/display latency.
- Fix only measured failures. Profile before considering direct Metal; any such change requires a new scoped task.

DO NOT: Add features, polish variants, or broad refactor without a failing criterion.

OUTPUT: Passing acceptance evidence and targeted fixes.

VERIFY: `xcodebuild test`; manual matrix; Instruments or Activity Monitor memory record; source audit of capture, copy, and panel creation paths.

DONE WHEN: Every Section 9 row passes or a precisely reproducible blocker is reported; memory plateaus during ten-minute run.

NEXT: T20.

### T20 — Local release package

GOAL: Produce a locally launchable release app and reproducible signing path.

DEPENDS ON: T19.

FILES / MODULES: `BlobbyCam.xcodeproj/`, `BlobbyCam/Resources/`, `blobby-cam`, `RELEASE.md`.

IMPLEMENT:
- Set Release build configuration, bundle ID/version, icon placeholder if needed, camera-only entitlement (leave App Sandbox disabled for the Terminal-first executable), and Hardened Runtime.
- Archive and smoke-test the `.app` plus local Terminal launcher. Document Developer ID signing, notarization, staple, and package steps using available credentials.
- If signing credentials are present, complete notarized local distribution; otherwise report that credential-dependent step as pending.

DO NOT: Add account/backend, Mac App Store workflow, recording, or final logo.

OUTPUT: Release `.app`, Terminal launcher, and exact reproducible packaging instructions.

VERIFY: Release archive succeeds; Terminal command runs from local folder, camera permission works, optional GUI opens; inspect entitlements and signing status.

DONE WHEN: Local release app runs with six features and Terminal-first controls; signing/notarization status is explicit and accurate.

NEXT: none.

## 6. PHASES

| PHASE | TASKS | GATE — do not advance unless |
|---|---|---|
| 0 — Project scaffold | T00–T01 | App/test targets build; contracts have one owner and six default IDs. |
| 1 — Camera | T02–T04 | Allow/deny and start/stop/reconnect work; latest frame is bounded. |
| 2 — Vision tracking | T05–T07 | Four face regions and two semantic hands yield timestamped snapshots. |
| 3 — Feature geometry | T08–T09 | In-bounds crops and grace/smoothing tests pass. |
| 4 — Native feature windows | T10–T11 | Six persistent nonactivating panels; mapping verified across screens. |
| 5 — Live crop rendering | T12 | One shared CI/Metal path displays distinct live crops without image encodes. |
| 6 — Tracking → windows | T13 | Six-window live vertical slice passes manual checks. |
| 7 — Control surfaces | T14–T18 | `./blobby-cam` starts ASCII arrow-key control; optional fixed-size Goofy UI appears only on request; every control works. |
| 8 — Stability / QA | T19 | Section 9 passes; ten-minute memory plateau documented. |
| 9 — Packaging / local release | T20 | Release archive and Terminal launcher run; signing/notarization status recorded. |

## 7. PARALLELIZATION MAP

Parallel work is safe only in separate branches/worktrees; each agent reads T01 contracts and edits only listed files. The integrator resolves shared project-file registration and runs a build after every merge.

PARALLEL GROUP A (after T01)

- T02 — permission
- T10 — native panels
- T14 — static menu shell **only if** its `AppDelegate.swift` edit is reserved for integration; otherwise run after T10

INTEGRATION GATE

- Merge T02, T10, T14 in that order; build; confirm the optional GUI shell and six hidden panels. Terminal-first behavior arrives at T18.

PARALLEL GROUP B (after T04)

- T05 — face extractor
- T06 — hand extractor

INTEGRATION GATE

- T07 — one Vision coordinator and shared snapshot verification.

PARALLEL GROUP C (after T07 and T10)

- T08 — pure crop geometry
- T09 — smoothing, if not already completed
- T11 — screen mapping

INTEGRATION GATE

- Merge T08, T09, T11; run their tests; then T12 and T13 sequentially.

Do not parallelize T16/T17/T18: they share Terminal contracts and lifecycle. T18 also owns AppDelegate integration, so no other agent may edit it concurrently.

## 8. INTEGRATION ORDER

```text
T00 → T01
       ├→ T02 → T03 → T04 ─┬→ T05 ─┐
       │                    └→ T06 ─┴→ T07 → T08 ─┐
       ├→ T09 ──────────────────────────────────────┤
       ├→ T10 → T11 ────────────────────────────────┤
       └→ T14 ────────────────────────────────┐     │
T04 + T08 + T10 → T12 ───────────────────────┼→ T13
T13 + T14 → T15 → T16 → T17 → T18 → T19 → T20 │
```

Operational merge sequence: T00, T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12, T13, T14, T15, T16, T17, T18, T19, T20. Parallel groups may change completion order, but integrate at the gates above and never merge two agents' independent rewrites of a shared file.

## 9. ACCEPTANCE MATRIX

| AREA | PASS CONDITION | CHECK |
|---|---|---|
| Camera permission allow | Prompt grants access and LIVE starts frames | Fresh permission state, manual |
| Camera permission deny | Clear status in ASCII menu; no capture or stale panels | Fresh/denied state, manual |
| Camera start | One session/output emits increasing timestamps | Runtime log/inspection |
| Camera stop/reconnect | Stop releases active stream; restart/interruption resumes | Manual unplug/restart where available |
| Left eye | Correct live crop and `LEFT EYE` title on displayed left | Manual face check |
| Right eye | Correct live crop and `RIGHT EYE` title on displayed right | Manual face check |
| Nose | Correct live crop and position | Manual face check |
| Mouth | Correct live crop and position | Manual speech/motion check |
| Left hand | Semantic left hand crop persists through crossing | Manual two-hand check |
| Right hand | Semantic right hand crop persists through crossing | Manual two-hand check |
| Six real windows | Six distinct persistent `NSPanel` identities, not canvas sprites | Runtime introspection + repeated show/hide |
| Native Terminal-like chrome | Six solid dark system titlebars with native traffic-light controls; no floating transparent labels | Visual comparison with user reference |
| No overlap | Feature panels never intersect each other or visible optional GUI | Layout tests + live visual check |
| Window size | Edge-drag resize persists across live frames; Terminal reports/resets that panel's size | Manual each panel + integration test |
| Window position | Terminal X/Y adjustment changes that panel's preferred position, respecting no-overlap | Keyboard check |
| Crop/padding | Terminal control changes source crop without moving window identity | Keyboard check |
| Crop zoom/pan | Terminal controls range from pupil to eye+brow framing and pan independently of window size | Manual eye check |
| Detection | Threshold changes eligibility; face uses observation/geometry | Manual + unit tests |
| Native feature resize | User can resize by dragging an edge; video fills the new content rect and tracking does not snap size back | Manual + integration test |
| Primary ASCII menu | `./blobby-cam` shows one legible 80×24 Terminal control view; arrow keys navigate/adjust every global and feature action | Local Terminal run |
| TUI selection/active color | Selected row is pink with `>`; activated toggle stays pink when selection moves away | Renderer test + local Terminal run |
| Terminal cleanup | Quit/Ctrl-C restores echo, canonical input, cursor, and screen | TTY smoke test |
| Optional Goofy UI | No GUI on TTY startup; `SHOW GOOFY UI` opens at most one fixed-size menu; hide returns to Terminal controls | Terminal command + manual |
| No hover magnification | Hover changes no window scale, frame, or zoom | Pointer sweep + frame observation |
| Smoothing | EMA reduces jitter without stale-position jumps | Deterministic tests + manual |
| Short loss grace | Brief miss holds; >250 ms miss hides/fades | Timestamp tests + manual |
| Semantic hands | `chirality` determines IDs, not screen order | Crossed hands test |
| Mirror correctness | Selfie mirror is default; all crop pixels and panel positions flip once; semantic IDs stay | Live left/right eye and hand check + toggle test |
| Keyboard focus | Feature panels do not activate or steal Terminal arrow input | Navigate TUI while panels appear |
| Spaces/full-screen | Panels follow specified all-Spaces/full-screen-auxiliary policy | Manual multi-Space test |
| Retina | Crop and position correct at non-1× scale | Retina screen manual |
| External display | Correct screen origin/scale and visible placement | Two-display manual |
| Memory plateau | Ten-minute live run stops trending upward | Instruments/Activity Monitor record |
| No per-frame image conversion | No JPEG/PNG/`NSImage` frame path | Source audit + allocation trace |
| One capture pipeline | One session and one video output | Source/runtime audit |
| No per-frame window recreation | Stable six object identities and allocation count | Runtime audit |

## 10. FAILURE / DEBUG ORDER

1. **Camera failure:** authorization → usage description/entitlement → device present → input/output configured once → session running → delegate queue → sample timestamp.
2. **No Vision landmarks:** nonnil pixel buffer → orientation → request errors → face/hand observation count → bounding box → required landmark/joint presence.
3. **Left/right mismatch:** log raw Vision chirality and face region IDs → inspect orientation → inspect mirror policy → confirm mirror applied once in `ScreenMapper`; never relabel by screen x.
4. **Wrong crop:** log normalized feature rect → face-bbox conversion → padding/clamp → normalized-to-pixel conversion → CI source extent.
5. **Wrong window position:** compare mapped center → screen origin/visible frame → backing scale → panel size → mirror/orientation step.
6. **Flicker:** raw confidence → show/hold thresholds → missing landmark policy → snapshot timestamp ordering → 250 ms grace → fade trigger.
7. **Latency:** capture drops → analysis queue age → Vision duration → CI render duration → GPU frame lifetime; profile before changing renderer architecture.
8. **Memory growth:** frame-store replacement → queued closures → Vision backlog → CI texture/buffer lifetime → panel/render-view count → allocations over ten minutes.
9. **Focus theft:** panel style mask → activation calls/order-front method → `becomesKeyOnlyIfNeeded` → content view first responder → repeat typing test.
10. **Terminal control failure:** check attached TTY → raw-mode setup → parsed escape sequence → selected menu row → emitted typed action → `AppState` update → redraw; restore termios before retrying.

## 11. SCOPE WATCHDOG

Stop the current branch and return to its task ID if it starts:

- Adding an unnecessary third-party runtime dependency or a second camera pipeline.
- Adding upload, recording/export, timeline, delay, echo/trail, hair segmentation, arbitrary object tracking, or backend/account work.
- Replacing persistent panels with one compositor canvas or recreating panels per frame.
- Building a custom Metal shader engine before measured CI rendering failure.
- Auto-opening Goofy UI in Terminal mode, adding a second GUI window, or making Goofy UI resizable.
- Capturing arrow keys globally or launching a second camera process for the TUI.
- Adding hover scale, zoom, resizing, or window magnification.
- Inventing per-landmark face confidence values.
- Inventing branded ASCII art before the user supplies it, or creating a final logo.
- Changing shared types without updating their sole owner and dependent tasks.

## 12. ITERATION 2 PARKING LOT

- Uploaded-video `FrameSource`.
- Temporal delay and frame ring using an owned pixel-buffer pool.
- Echoes/trails and richer motion behavior.
- Hair segmentation.
- Recording/export.
- Smile-driven window scaling and richer motion behavior.
- Variable feature-window count and tracking of three to four faces.
- Custom windows and manual pinning of windows on screen.

None is a v0 task.

## 13. LUNA AGENT TASK PROMPT TEMPLATE

```text
You are implementing Blobby Cam task {TASK_ID}.

Current repo state: {CURRENT_REPO_STATE}
Known issues: {KNOWN_ISSUES}

1. Read fun-tracking.md (the research handoff in the repo), any supplied full blobby-cam-native-macos-research.md, and BLOBBY_CAM_BUILD_PLAN.md.
2. Inspect existing code and, if this folder is a Git repository, git status before editing.
3. Execute ONLY {TASK_ID}, including its dependencies check, FILES / MODULES, IMPLEMENT, DO NOT, VERIFY, and DONE WHEN.
4. Preserve the established shared interfaces and their single owners. If the research and plan conflict, report the exact conflict and stop the affected change rather than re-architecting.
5. Build and run the task's tests/manual checks. Fix errors caused by this task.
6. Do not begin the next task or add future features.
7. Report: changed files; verification performed and results; remaining issue, if any; whether every DONE WHEN criterion passed.
```

## 14. FIRST AGENT HANDOFF

```text
You are implementing Blobby Cam task T00 — Native project scaffold.

Historical first-agent state: the project folder contained fun-tracking.md and BLOBBY_CAM_BUILD_PLAN.md, with no application source or Xcode project. Work only in this project folder. The current source tree supersedes this historical handoff text.
Known issues: fun-tracking.md links to a fuller blobby-cam-native-macos-research.md that is not currently in the repo. T00 is fully specified by the available research handoff and plan; do not invent requirements from the missing linked file.

1. Read fun-tracking.md and BLOBBY_CAM_BUILD_PLAN.md. Also read blobby-cam-native-macos-research.md if it is supplied before starting.
2. Inspect existing files before changing anything. Check git status only if this folder is a Git repository; it currently is not.
3. Execute ONLY T00 as specified in Section 5. Create the native macOS 14+ Swift/Xcode app and test targets, one placeholder menu window, camera usage text, and camera-only entitlement without App Sandbox.
4. Preserve the plan's architecture and do not add capture, tracking, feature windows, final logo, third-party dependencies, or later tasks.
5. Run xcodebuild -list, build app and test targets, launch the app, and fix errors caused by T00.
6. Do not begin T01.
7. Report changed files; verification and results; remaining issue, if any; and whether all T00 DONE WHEN criteria passed.
```
