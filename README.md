<div align="center">
  <img src="docs/icon.png" width="128" alt="Display Tuner icon" />
  <h1>Display Tuner</h1>
  <p><strong>Research-based display settings for gaming and editing on the Mac.</strong></p>
  <p><a href="https://github.com/BireshwarChakravarty/DisplayTuner/releases/latest">Download Display Tuner 1.1</a> · <a href="DisplayTuner/README.md">Technical guide & research</a></p>
</div>

## What it does

Display Tuner is built for one monitor, the **Acer Nitro XV272K V5**, on an Apple Silicon Mac. Pick what you're doing, review exactly what will change, and apply it, with your previous settings saved for Undo. Other screens are listed but never touched.

- **Seven presets:** Competitive Gaming, Immersive Gaming, Photo Editing, Video Editing, MacBook Look, Max Brightness and Everyday.
- **Research you can check:** every fact and monitor-menu step comes from Acer's manuals, VESA's DisplayHDR list, instrumented reviews or Apple's support pages, and links to its source. Figures measured on sibling models say which model.
- **Safe by design:** the app writes only brightness and contrast over DDC/CI (the controls Acer documents), at least 50 ms apart, never while the display sleeps, and never above the value the monitor reports as its maximum. A new resolution lasts for the session until you keep it.
- **A checklist for what only you can do:** the monitor's menu (Color Space, Max Brightness, Over Drive…), System Settings and the cable.
- **Finds the free win:** if the Acer runs slower than it can at the same resolution, it offers the fix in one click.
- **Also:** automatic presets for games and editors, saved presets, test patterns, a Control Center-style menu-bar panel with live brightness, activity history and diagnostics export.

## Install

Download the ZIP from [Releases](https://github.com/BireshwarChakravarty/DisplayTuner/releases), unzip, and drag **Display Tuner.app** to Applications. Requires Apple Silicon and macOS 26 or later.

The community build is ad-hoc signed and not notarized. macOS may ask you to approve opening it under **System Settings → Privacy & Security**. Verify the download using the supplied SHA256SUMS.txt.

## Build

```sh
cd DisplayTuner
bash make-app.sh --package  # build a signed app and ZIP without installing
bash make-app.sh --install  # explicitly install and open the app
```

Build with an Xcode 26 SDK or later. The deployment target is macOS 26. The app icon is drawn by `scripts/make-icon.py` (Python with Pillow and NumPy), stored as a versioned base64 PNG, and turned into `AppIcon.icns` by the packaging script.

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

Settings, presets and the last 100 operation results stay on your Mac. There is no analytics service or account requirement. DDC and Night Shift use private macOS APIs. The app doesn't estimate brightness in cd/m²: the V5's brightness curve isn't published, so only a colorimeter gives exact figures. Calibrated displays keep their hardware levels and picture settings.

Read the [release notes](RELEASE_NOTES.md) and [technical guide](DisplayTuner/README.md) for limits, sources and monitor-specific advice.

## License

[MIT](LICENSE) · Copyright © 2026 Bireshwar Chakravarty.
