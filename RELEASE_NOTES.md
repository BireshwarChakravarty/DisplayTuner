# Display Tuner 1.0

Research-based display settings for gaming and editing on Apple Silicon Macs. Pick a screen, choose what you're doing, review exactly what will change, and apply it, with your previous settings saved for Undo.

## Highlights

- **Five presets:** Competitive Gaming, Immersive Gaming, Photo Editing, Video Editing and Everyday. Each tile previews what it sets, for example "160 Hz · sRGB · 120 nits", and room lighting sets the brightness target.
- **Overview at a glance:** a colour-gamut chart of your display against sRGB and P3, and readouts for refresh rate, desktop size, colour mode and brightness in estimated nits.
- **Finds the free win:** if a screen runs slower than it can at the same resolution (for example 60 Hz instead of 160 Hz), it says so with a one-click fix.
- **Changes shown before → after,** each with its reason and source, and a switch to leave any one out.
- **A checklist for what only you can do:** monitor menu settings, System Settings, cable and app settings, with progress remembered per display.
- **Asks your monitor what it supports** over DDC/CI. On monitors that list an sRGB preset, editing switches the monitor's picture mode for you and checks the result; values the monitor doesn't list are never offered.
- **Automatic presets (optional):** games and photo/video editors switch your screens' preset when they come to the front. Resolution and refresh rate never change automatically.
- **Safe by design:** settings are saved before every change; resolution changes revert after 15 seconds unless you keep them; calibration profiles are never touched; Undo and Restore Originals are always available.
- **Menu bar panel, Control Center style:** your screens with their mode and preset, a one-tap switch to 160 Hz, round preset buttons, a live brightness slider that moves the monitor's backlight with a nits readout, and Night Shift, room lighting and auto-preset tiles.
- **Also:** saved presets, full-screen test patterns, an activity log, diagnostics export, light and dark appearance.

## Install

Download **DisplayTuner-1.0.0-macOS.zip**, unzip it, and move **Display Tuner.app** to Applications. Requires Apple Silicon and macOS 26 or later. The app is ad-hoc signed, not notarized: on first launch, approve it in System Settings → Privacy & Security. SHA256SUMS.txt accompanies the download.

## Limits

DDC/CI support varies by monitor, cable and dock. Night Shift and Apple Silicon DDC use private macOS APIs. Brightness figures are estimates from the panel's rated peak and gamut figures come from its profile; only a colorimeter gives exact values.
