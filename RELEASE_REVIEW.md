# Pre-release review

Reviewed: 2026-10-04. This is a local source review, not a public GitHub release.

## Verified

| Check | Result |
|---|---|
| Xcode Debug tests | PASS: 116 tests, 0 failures on 2026-10-04 (`QA_NOTES.md`) |
| Local unsigned Release build | PASS: Apple silicon/macOS, `CODE_SIGNING_ALLOWED=NO`, including window copies |
| Xcode static analysis | PASS: Debug `xcodebuild analyze`, no diagnostics |
| One native camera pipeline, six initial persistent AppKit panels plus copies | PASS: source audit and focused tests, including 20 mouth windows |
| Git file hygiene | PASS: `.build`, Xcode user state, results, archives, logs, and credential files excluded |
| Local developer launcher | PASS: `./blobby-cam` builds and execs the app; user has exercised live camera/TUI |
| Preview script syntax and installer paths | PASS: both scripts pass `sh -n`; a fixture ZIP verified checksum checking, `--no-run` installation, launcher argument forwarding, and clear errors for a missing ZIP, changed ZIP, and repeat install. |
| Small preview package | PASS: fresh 2026-10-04 unsigned arm64 app 3.2 MB, ZIP 872 KB. Package checksum passed. The installer path and executable hash were verified with the 2026-09-27 package. `.build` is outside the archive. |

## Before public GitHub release

| Priority | Item | Acceptance |
|---|---|---|
| Blocker | Fresh live smoke after copies, close fix, and HIDE UI BAR | Face and both hands stay correctly framed; 80×24 TUI guide remains visible; create/resize/close 20 mouth copies repeatedly without a crash; hidden-bar video drag and edge resize work. |
| Blocker | Ten-minute runtime check | Camera runs continuously, memory plateaus, and no feature window steals Terminal keyboard focus. Record numbers in `QA_NOTES.md`. |
| Blocker | Distribution path | Choose a GitHub repository URL and deliver a signed/notarized app or a clearly documented source-only install. Test the exact one-command install on a clean Mac. |
| Blocker | GitHub access | No remote is configured. `gh auth status` reports an invalid token for the active account; re-authenticate before creating a remote, pushing, or opening a PR. |
| Blocker | License decision | Add the user's chosen license, or explicitly publish without one. Do not invent a license. |
| Follow-up | Release identity | Replace the generic developer icon when the final logo is ready; choose the first public version and release notes. |
| Follow-up | Broader hardware | Check Intel Mac, macOS 14, and external displays if these are promised in release notes. Current verified build is Apple silicon on macOS 27. |

## Distribution boundary

The current `./blobby-cam` command is a local developer launcher. It rebuilds from source and requires Xcode. The local preview package scripts produce an unsigned app and are not a public GitHub installer. The requested GitHub install-and-run command does not yet exist. Do not advertise it in the README or release notes until the hosted artifact, integrity check, signing/notarization policy, and clean-machine install have been verified.

Old generated Xcode caches were pruned from `.build` after packaging: local cache size fell from about 3.9 GB to 1.4 GB. The active Debug, Release, and latest integrated test data were retained. `dist/` and `.build/` are both ignored by Git.

The build plan and research handoff are historical documents. Their original external research file is not present; current behavior is documented in the README and source.

The camera permission text is in `BlobbyCam/Info.plist`. The app has no upload, backend, or recording path. The build uses an unsandboxed Terminal-first target because raw-mode input requires access to the controlling TTY; camera access is still governed by macOS permission.
