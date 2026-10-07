# Preview release review — 2026-10-07

## Ready for 0.1.0 preview

| Check | Evidence |
|---|---|
| Debug tests | 120 passed, 0 failed, 0 skipped; see QA_NOTES.md |
| Release with supplied icon | 0.1.0/build 1, valid Icon Composer output, .icns + Assets.car + bundle icon keys |
| Package | 2.5 MB ZIP / 5.3 MB app; includes Terminal launcher, installer and both licenses |
| Install | Real ZIP checksum and install verified under project-local test root; installed executable equals built executable |
| Corrupt download | Rejected before installation |
| Piped Terminal install | PTY test confirms input/output TTY restoration using a test payload |
| GitHub access | Network-enabled gh authentication works; repo created in kirilldodon2-ux |
| License | User approved MIT; official bundled Syphon retains BSD |
| Branding/docs | Original user icon, user-approved live screenshot, README + release notes |

## Disclosed preview limits

- Unsigned and not notarized. No Gatekeeper disabling or quarantine stripping in installer. A clean-Mac first-launch approval flow is not verified.
- Apple silicon/macOS 27 tested. macOS 14 is the build minimum, not a verified runtime result; no Intel download is promised.
- Syphon sources mix/flicker in the user's Ghost Arcade setup. Three official Metal clients pass isolation tests, but the integration cause remains unresolved. Syphon is OFF by default and described as experimental.
- Long-run memory/GPU and extensive external-display/projector checks remain pending.

## Publication

Repository: https://github.com/kirilldodon2-ux/blobby-cam

Release tag: `v0.1.0-preview.1` (prerelease). Upload the ZIP + matching SHA-256 and verify the real hosted installer with `--no-run` into a project-local test root. Do not claim a clean-Mac launch test from this download check.

Git ignores .build/dist/Xcode user state/credentials. Original local development history and backup commits are retained.
