<div align="center">
  <img src="https://github.com/BireshwarChakravarty/DisplayTuner/releases/download/v2.0.1/DisplayTuner-Icon.png" width="128" alt="Display Tuner icon" />
  <h1>Display Tuner</h1>
  <p><strong>Your display, refined.</strong></p>
  <p>A native Mac workspace for better display settings, clearer decisions and a more comfortable picture.</p>
  <p><a href="https://github.com/BireshwarChakravarty/DisplayTuner/releases/latest">Download the latest release</a> · <a href="DisplayTuner/README.md">Technical guide & research</a></p>
</div>

## A studio for every screen

Pick a display, choose what you're doing, review exactly what will change, and apply it, with your previous settings saved for Undo. It looks and works like a built-in Mac app. Display Tuner requires macOS 26 or later.

- **Asks your monitor what it supports** over DDC/CI, so hardware changes are only offered when the monitor lists them; on monitors that list an sRGB preset, editing switches it for you.
- **Automatic presets (optional):** games and photo/video editors switch your screens' preset when they come to the front.

- **Five activities:** Competitive Gaming, Immersive Gaming, Photo Editing, Video Editing and Everyday.
- **Fine-tune:** stage hardware brightness, contrast, resolution and refresh adjustments.
- **Saved presets:** keep named setups for your own displays and review before applying them.
- **Test patterns:** inspect gradients, grayscale, shadow detail, highlight detail, grid sharpness and colour bars full screen.
- **Understand the advice:** sources, rationale, capability detection and manual monitor-menu steps.
- **Stay in control:** Undo, original settings, confirmation countdowns, calibration protection and interrupted-change recovery.
- **Mac conveniences:** menu-bar presets, display identification, activity history, diagnostics export, optional launch at login and appearance preferences.

## Install

Download the ZIP from [Releases](https://github.com/BireshwarChakravarty/DisplayTuner/releases), unzip, and drag **Display Tuner.app** to Applications. Requires Apple Silicon and macOS 26 or later.

The community build is ad-hoc signed and not notarized. macOS may ask you to approve opening it under **System Settings → Privacy & Security**. Verify the download using the supplied SHA256SUMS.txt.

## Build

```sh
cd DisplayTuner
bash make-app.sh --package  # build a signed app and ZIP without installing
bash make-app.sh --install  # explicitly install and open the app
```

Build with an Xcode 26 SDK or later for Liquid Glass. The deployment target is macOS 26. The packaging script reconstructs the app icon from its versioned base64 PNG source, which allows lossless asset publishing through the text-only repository connector.

```sh
swift test --package-path DisplayTuner
python3 scripts/test-core-portable.py  # fallback when Command Line Tools lack XCTest
```

## Explore safely

```sh
open "DisplayTuner/.build/app/Display Tuner.app" --args --demo
```

Demo displays are clearly labeled. Hardware writes, saved presets and full-screen patterns are disabled in this mode.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1–⌘4 | Switch workspace sections |
| ⌘R | Rescan displays and DDC controls |
| ⌘Return | Apply the selected display’s tuning plan |
| ⌘Z | Undo last apply |
| ⇧⌘E | Export diagnostics |
| Esc | Revert an unconfirmed mode change / close a test pattern |

## Compatibility and privacy

Settings, presets and the last 100 operation results stay on your Mac. There is no analytics service or account requirement. DDC and Night Shift support depend on the hardware and private macOS APIs. Brightness and gamut figures are estimates, not calibration measurements. Calibrated displays keep their hardware levels and picture modes.

Read the [release notes](RELEASE_NOTES.md) and [technical guide](DisplayTuner/README.md) for limits, sources and monitor-specific advice.

## License

[MIT](LICENSE) · Copyright © 2026 Bireshwar Chakravarty.
