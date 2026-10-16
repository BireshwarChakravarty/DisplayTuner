# Display Tuner 2.0.1 — Your display, refined

Version 2.0.1 additionally blocks preset deletion in the demo workspace.

The repository now includes an MIT license. A license-bearing v2.0.2 package is prepared on `codex/mit-license-release` and awaits publication.

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

Download **DisplayTuner-2.0.1-macOS.zip**, unzip it, and move **Display Tuner.app** to Applications.

Requires **Apple Silicon and macOS 14+**. Liquid Glass requires macOS 26+. The app is ad-hoc signed, **not Developer ID signed or notarized**. macOS may require you to approve it in System Settings → Privacy & Security after the first launch attempt. No security settings need to be disabled.

SHA256SUMS.txt accompanies the download.

## Validation and limits

The core regression suite contains 46 tests covering recommendations, colour maths, ICC parsing, mode selection, packet handling, identity matching and snapshot compatibility. Local validation executes the same method bodies through the portable assertion runner; release CI also runs XCTest before publishing.

DDC/CI support varies by monitor, connection and macOS version. Night Shift and Apple Silicon DDC use private APIs. Visual test patterns and rated-brightness estimates do not replace colorimeter calibration. Hardware behaviour still needs verification on the intended monitor setup; it is not covered by the simulated workspace.
