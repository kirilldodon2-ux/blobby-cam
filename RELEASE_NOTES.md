# Blobby Cam 0.1.0 — first preview

A few windows. A lot of face.

Your webcam's eyes, nose, mouth, and hands become independent native macOS windows. Move them, stretch them, freeze a crop, or spawn up to 32 copies of each feature. Control everything from the ASCII Terminal menu, or open the optional Goofy UI.

## In this preview

- User-created rainbow Blobby Cam icon, including Icon Composer assets.
- Native windows, manual placement and resizing, per-copy crop/freeze controls.
- Optional titlebar hiding and automatic-follow/crop-scale modes.
- Experimental per-instance Syphon sources for projector-mapping experiments.
- Prebuilt Apple silicon app, double-click Terminal launcher, and checksum-verified installer.
- Open source under MIT; bundled official Syphon uses BSD.

## Start

Download the ZIP and its `.sha256`. Unzip and double-click **Launch Blobby Cam.command**. Camera LIVE starts automatically after permission. Use arrow keys; Enter opens window settings; Esc goes back. QUIT or Ctrl-C exits.

Or install and launch directly from Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/kirilldodon2-ux/blobby-cam/v0.1.0-preview.1/scripts/install.sh | sh -s -- kirilldodon2-ux/blobby-cam
```

The app download does not require Xcode. Source builds do.

## Preview limits

- Apple silicon verified on macOS 27; target minimum macOS 14 is not yet verified on that OS. No tested Intel download.
- This app is unsigned and not notarized. macOS may require its normal Privacy & Security approval before launch.
- Syphon is OFF by default. Ghost Arcade has shown mixed/flickering sources; that integration issue is unresolved. Do not rely on it for a performance yet.
- Long runs with many windows/receiver layers and external-display behavior still need broader testing.

Licenses and a quick-start file are included in the ZIP.
