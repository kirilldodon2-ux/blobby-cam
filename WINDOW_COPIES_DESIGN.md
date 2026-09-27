# Feature window copies — implementation design

Status: implemented in the `dodon/window-copies` branch; automated tests pass. Live camera and extended performance checks for 20 copies are still pending.

## User-visible behavior

- Every feature has a `WINDOWS` count. The default remains 1; the feature's ON/OFF switch controls visibility without discarding its count.
- Increasing the count creates additional real, titled, nonactivating `NSPanel` objects such as `MOUTH 2` and `MOUTH 3`. Each can be dragged and resized natively. No panel is created during a camera frame update.
- All copies of one feature use the same camera frame and the same Vision detection. A new copy inherits the current settings of the first copy, including its custom window size and crop. After spawning, its window size, position, crop zoom/pan/padding, detection threshold, ON/OFF, and FREEZE FRAME can be changed independently in that copy's deeper settings. A separate confidence lifecycle per copy can use the shared detection without rerunning Vision.
- With AUTO FOLLOW OFF (default), manually placed copies never snap back. New copies get a free initial position near their feature when space permits. Existing windows keep their positions when another copy is added or removed.
- Closing one copy with its red button removes that exact copy and updates `WINDOWS` in both UIs. Closing the last copy switches the feature OFF while retaining its panel for re-enabling.
- Reducing the count through a menu removes the most recently added copy first. Increasing it again creates a fresh copy without moving the survivors.
- Window titles use current ordinal labels for clarity; stable internal IDs do not depend on those labels.
- Retired extra `NSPanel` objects are hidden in a bounded per-feature reuse pool. Reuse assigns a new stable ID and render view without replacing any surviving panel; the six original panels stay allocated.

## Ownership and data flow

| Owner | Contract |
|---|---|
| `AppState` | Owns each feature's ordered stable window IDs and each copy's configuration. It is the only source of truth for which IDs should exist and what each copy displays. |
| `FeatureWindowManager` | Owns one persistent panel per active ID. Reconciles IDs only after a count/close action, then shows/hides/moves panels. Reports native drag/resize changes to `AppState`; it does not own a second configuration copy. |
| `SharedRenderer` | Wraps one incoming pixel buffer per frame and builds a lazy Core Image crop for each visible instance from the shared source. Frozen instances retain only their last frame. Copies never create a camera or Vision pipeline. |
| Terminal/Goofy UI | Edits count and selected-copy settings through `AppState`; both show the same values. No UI stores a separate count or crop setting. |

`WindowInstanceID = (FeatureID, monotonic serial)` identifies a native panel. Removing a middle copy removes its ID, not an ordinal slot. This prevents another panel from being silently replaced or teleported. The window title may be renumbered after removal; the ID and frame stay the same.

## Implementation order

1. Add the stable instance-ID, count, and per-copy configuration contract. Preserve one default instance for each feature and the existing ON/OFF behavior. Creating copies clones the first copy's current configuration once; later edits never fan out.
2. Let the shared renderer register multiple weak render views, keyed by instance ID. Use one source `CIImage` wrapper per camera frame, make lazy crop graphs per instance, and retain frozen frames only for frozen instances.
3. Refactor the window manager to reconcile panels by instance ID. Preserve the existing first-window behavior and create or retire extra panels only on explicit count changes. Red close removes exactly its ID; the last panel becomes OFF but is retained for re-enabling.
4. Add collision-aware initial placement for new copies without modifying manually placed frames. AUTO FOLLOW should preserve each copy's relative offset if enabled.
5. TUI: feature row → instance list (`WINDOWS` count and `MOUTH 1–5`) → selected instance settings. Keep navigation hints visible at 80×24. Goofy UI: count control and expandable settings per copy within the one fixed-size scrollable menu.
6. Verify panel identity, close-middle behavior, count reduction, manual resize/drag persistence, independent crops/freeze, TUI fit, and no extra capture or Vision pipeline. Perform a live camera check with several copies of eyes and mouth.

## Limits and edge cases

- A display may not have enough free area for many nonoverlapping windows. Do not move existing manually placed windows to make room; keep a deterministic best-effort spawn position and make the physical limit visible in the UI if needed.
- FREEZE FRAME applies to the selected copy. Turning LIVE OFF retains each frozen copy and hides ordinary copies.
- A single feature may be OFF while its configured count remains above 1. Turning it ON restores the same active instance IDs and positions.
- No settings persistence across app restarts is part of this change; current v0 state is in memory.

## Open questions

- The first version allows 1–32 copies per feature. The user's 20-mouth example must work; performance at that count still needs a live check before public release.
