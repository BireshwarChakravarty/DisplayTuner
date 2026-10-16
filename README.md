<div align="center">
  <img src="https://github.com/BireshwarChakravarty/DisplayTuner/releases/download/v2.0.0/DisplayTuner-Icon.png" width="128" alt="Display Tuner icon" />
  <h1>Display Tuner</h1>
  <p><strong>Your display, refined.</strong></p>
  <p>A native Mac workspace for better display settings, clearer decisions and a more comfortable picture.</p>
  <p><a href="https://github.com/BireshwarChakravarty/DisplayTuner/releases/latest">Download the latest release</a> · <a href="DisplayTuner/README.md">Technical guide & research</a></p>
</div>

## A studio for every screen

See connected displays and their capabilities, choose an activity, inspect the suggested changes, and apply them with a saved rollback state. Modern Liquid Glass controls on macOS 26+ sit above a readable display workspace; macOS 14–15 use native translucent materials.

- **Five activities:** Competitive Gaming, Immersive Gaming, Photo Editing, Video Editing and Everyday.
- **Fine-tune:** stage hardware brightness, contrast, resolution and refresh adjustments.
- **Saved presets:** keep named setups for your own displays and review before applying them.
- **Test patterns:** inspect gradients, grayscale, shadow detail, highlight detail, grid sharpness and colour bars full screen.
- **Understand the advice:** sources, rationale, capability detection and manual monitor-menu steps.
- **Stay in control:** Undo, original settings, confirmation countdowns, calibration protection and interrupted-change recovery.
- **Mac conveniences:** menu-bar presets, display identification, activity history, diagnostics export, optional launch at login and appearance preferences.

## Install

Download the ZIP from [Releases](https://github.com/BireshwarChakravarty/DisplayTuner/releases), unzip, and drag **Display Tuner.app** to Applications. Requires Apple Silicon and macOS 14 or later. Liquid Glass requires macOS 26+.

The community build is ad-hoc signed and not notarized. macOS may ask you to approve opening it under **System Settings → Privacy & Security**. Verify the download using the supplied SHA256SUMS.txt.

## Build

```sh
cd DisplayTuner
bash make-app.sh --package  # build a signed app and ZIP without installing
bash make-app.sh --install  # explicitly install and open the app
```

Build with an Xcode 26 SDK or later for Liquid Glass. The deployment target remains macOS 14. The packaging script reconstructs the app icon from its versioned base64 PNG source, which allows lossless asset publishing through the text-only repository connector.

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
