# Syphon dependency

Official source: https://github.com/Syphon/Syphon-Framework
Pinned commit: f4761677a45b8034a3c2069ec0f3d2553da81fba
Downloaded: 2026-10-04 from the GitHub commit archive.
License: BSD; see Syphon/License.txt. A copy is bundled in the app resources.

The upstream implementation is unmodified and built as an Xcode subproject. Its project deployment target is pinned to macOS 14.0 to match Blobby Cam, and Debug builds include both Mac architectures to match the parent target. Metal Toolchain is required by upstream's .metal shader. No dependency download happens when Blobby Cam runs.
