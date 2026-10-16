# Display Tuner 2.1.0 — native redesign, monitor capabilities and automatic presets

## A native Mac app
- Redesigned in the style of System Settings: a standard sidebar with your displays and a Library (presets, test patterns, activity), and one page per display in task order: what you're doing, the changes, the steps for the monitor, System Settings, cable and apps, then adjustments and display details.
- Apply and Undo are always visible at the bottom, with a count of the selected changes. Identify, Save as Preset, Restore and Diagnostics are in the ⋯ menu.
- When a display runs slower than it can at the same size (for example 60 Hz instead of 160 Hz), the page says so at the top with a one-click fix.
- Follows the system appearance and accent colour. The illustration, glow backdrop and marketing copy are gone.

## Asks the monitor what it supports
- Reads each monitor's DDC/CI capabilities list. If the monitor lists sRGB among its colour presets, the editing presets switch its picture mode for you and check the result, and the gaming presets return it to the preset it had before. Values the monitor doesn't list are never offered.
- What the monitor reports is shown under About this display and in diagnostics.

## Automatic presets (optional)
- Settings → Automatic presets: games (by App Store category or Steam library) and photo and video editors (Lightroom, Photoshop, Capture One, Final Cut Pro, DaVinci Resolve and others) switch every external screen's preset when they come to the front. Leaving them returns to your own preset.
- Resolution and refresh rate never change automatically. If the colour profile changes but the monitor's picture mode can't be switched over DDC, a card on that screen says which setting to change.

## Also
- Fix the MCCS code used for "restore factory brightness/contrast" (0x05).
- CI captures screenshots of the demo workspace for design review.

## macOS 26 and later

- Require macOS 26.0 or later in the Swift package deployment target, app bundle and compiled executable.
- Use native Liquid Glass directly; remove the compatibility fallback for older macOS versions.
- Preserve the opaque accessibility surface when Reduce Transparency is enabled.
- Update Settings and installation documentation to match the new requirement.

Requires Apple Silicon and macOS 26 or later. The app is ad-hoc signed, not notarized: on first launch, approve it in System Settings → Privacy & Security.

---

# Display Tuner 2.0.2 — Your display, refined

Version 2.0.2 includes the MIT license in the source, app bundle and release downloads. It also includes the demo preset protection from 2.0.1.

A redesigned native macOS workspace for understanding and tuning your displays.

## New in 2.0

- Display Studio with an illustrated monitor preview, capability cards, a translucent sidebar and a floating Liquid Glass action bar on macOS 26+. Native material fallback on macOS 14–15.
- A new glass monitor app icon, bundled at sizes from 16 to 1024 pixels.
- Five activity presets with sourced explanations and separate manual setup instructions.
- Staged brightness and contrast sliders: review adjustments before applying them.
- Saved, named presets for each display, including activity, room lighting, mode and hardware levels.
- Six full-screen test patterns: gradient, grayscale, shadows, highlights, grid and colour bars. Escape closes the pattern.
- An on-device activity log, diagnostics export, display identification and keyboard shortcuts.
- Dark, light and system appearance; optional launch at login.
- An isolated `--demo` workspace for exploring the app without touching display hardware.

## Safety fixes

- Reject weak and tied DDC matches; refuse ambiguous identical displays without a distinguishing serial.
- Use persistent display UUIDs to avoid serial-less display collisions.
- Preserve calibrated profiles **and** their monitor hardware settings and picture mode.
- Stop before writing if rollback values cannot be read or snapshots cannot be persisted.
- Isolate pending confirmation state, block competing applies, revert before normal quit and retain interrupted transactions for recovery on the next launch.
- Capture only settings actually changed; merge original profile state when it is first modified.
- Read back hardware writes and restores; report unverified writes rather than presenting them as successful.
- Rescan after connection changes and explicit refresh; do not send DDC commands to mirrored displays.

## Install

Download **DisplayTuner-2.0.2-macOS.zip**, unzip it, and move **Display Tuner.app** to Applications.

Requires **Apple Silicon and macOS 14+**. Liquid Glass requires macOS 26+. The app is ad-hoc signed, **not Developer ID signed or notarized**. macOS may require you to approve it in System Settings → Privacy & Security after the first launch attempt. No security settings need to be disabled.

SHA256SUMS.txt accompanies the download.

## Validation and limits

The core regression suite contains 46 tests covering recommendations, colour maths, ICC parsing, mode selection, packet handling, identity matching and snapshot compatibility. Local validation executes the same method bodies through the portable assertion runner; release CI also runs XCTest before publishing.

DDC/CI support varies by monitor, connection and macOS version. Night Shift and Apple Silicon DDC use private APIs. Visual test patterns and rated-brightness estimates do not replace colorimeter calibration. Hardware behaviour still needs verification on the intended monitor setup; it is not covered by the simulated workspace.
