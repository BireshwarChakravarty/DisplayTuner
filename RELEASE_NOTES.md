# Display Tuner 1.2

Research-based display settings for gaming and editing on Apple Silicon Macs. Pick a screen, choose what you're doing, review exactly what will change, and apply it, with your previous settings saved for Undo.

## New in 1.2

- **Built for the Acer Nitro XV272K V5.** Every fact and menu step was checked against a primary source: Acer's manuals, VESA's DisplayHDR list, instrumented reviews of its siblings (labelled with the model) and Apple's support pages. Claims that couldn't be confirmed were removed. Other screens are left alone.
- **Max Brightness preset:** full backlight with the factory picture, plus the monitor's own Max Brightness switch, which Acer ships Off to save energy.
- **Safer DDC/CI:** only brightness and contrast are written; at least 50 ms between commands; nothing while the display sleeps or for 3 seconds after it wakes; new resolutions last for the session until you keep them.
- **Correct menu paths:** Color → Color Space (General or sRGB), Picture → Max Brightness, Gaming → Variable Refresh Rate, System → Max Refresh Rate and DFR.
- **No more estimated nits.** The V5's brightness curve isn't published, so presets only set brightness where it's unambiguous (100%).
- **Liquid Glass design:** an edge-to-edge hero, glass controls, preset cards, a research inspector and a floating Apply bar.

## Highlights

- **Seven presets:** Competitive Gaming, Immersive Gaming, Photo Editing, Video Editing, MacBook Look, Max Brightness and Everyday.
- **Changes shown before → after,** each with its reason and source, and a switch to leave any one out.
- **A checklist for what only you can do:** monitor menu settings, System Settings and the cable, with progress remembered.
- **Automatic presets (optional):** games and photo/video editors switch the preset when they come to the front. Resolution and refresh rate never change automatically.
- **Undo, Restore Originals, a keep-or-revert countdown** for resolution changes, and calibration protection.
- **Also:** saved presets, full-screen test patterns, a Control Center-style menu-bar panel with live brightness, an activity log, diagnostics export, light and dark appearance.

## Install

Download **DisplayTuner-1.2.0-macOS.zip**, unzip it, and move **Display Tuner.app** to Applications. Requires Apple Silicon and macOS 26 or later. The app is ad-hoc signed, not notarized: on first launch, approve it in System Settings → Privacy & Security. SHA256SUMS.txt accompanies the download.

## Limits

Acer's own manual for the V5 couldn't be obtained, so menu paths follow the 2024 XV275K manual (the closest model with the same DFR switch); your menu may differ slightly. No instrumented review of the V5 exists yet. Night Shift and Apple Silicon DDC use private macOS APIs. Only a colorimeter gives exact brightness and colour figures.
