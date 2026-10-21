> **Version 1.1:** See the [main README](../README.md) for the app's features, saved presets, test patterns, automatic presets and release instructions. Calibration protection also preserves hardware levels and monitor picture mode.

# Display Tuner

A Mac app that finds the best settings for each of your screens, using
published research for your monitor model, and applies them when you pick
what you're doing: **Competitive Gaming**, **Immersive Gaming**,
**Photo Editing**, **Video Editing**, **MacBook Look** or **Everyday**.
**MacBook Look** matches a MacBook Air's Retina screen as closely as the panel allows: native P3 colour, colour-managed by macOS, at up to full brightness (a MacBook Air reaches 500 nits), D65 white, gamma 2.2, Night Shift and HDR off.

It starts with the monitors on this desk:

| Screen | What the app knows |
|---|---|
| **Acer Nitro XV272K V5** | 27" 4K IPS, 160 Hz (320 Hz at 1080p with DFR), wide gamut (~90–95% DCI-P3), factory-calibrated sRGB mode, DisplayHDR 400, FreeSync Premium, DDC/CI works. |
| **ARZOPA portable** | sRGB-class IPS, no DDC/CI. Mirrors the Acer. |

Any other display still gets sensible settings, worked out from what it reports
about itself: its modes, size, colour gamut (read from its ICC/EDID profile),
HDR headroom and DDC/CI controls.

## What it does

1. **Detects** every screen: modes, physical size, gamut (as % of sRGB and
   Display P3), colour profile, HDR, and DDC/CI support. It also notes which
   screen mirrors which.
2. **Recommends** settings for the preset you pick, with the reason and source
   for each.
3. **Applies** the changes you tick, after saving your current settings:

   | Setting | How |
   |---|---|
   | Resolution & refresh rate | CoreGraphics (same as System Settings). Gaming takes the fastest rate at full resolution; Video Editing takes 120 Hz, a multiple of 24 and 30 fps, so playback doesn't judder. Your desktop size is kept if it's sharp. |
   | Colour profile | ColorSync. **sRGB** for editing, paired with the Acer's sRGB mode. The **display's own** profile for gaming. A calibration profile you made yourself is never touched. |
   | Brightness & contrast | DDC/CI. Editing targets 90 / 120 / 160 cd/m² for a dim / normal / bright room. Contrast goes back to the Acer's factory 50, which doesn't clip whites. Values are read back to check the monitor accepted them. |
   | Night Shift | Switched off for editing, since it moves the white point off D65. Undo turns it back on. |
   | Monitor colour preset | DDC/CI, *experimental* and off by default. Some monitors switch to sRGB mode when asked. |

4. **Tells you what only you can change**: the monitor's own menu (sRGB /
   Standard mode, Over Drive **Normal**, Adaptive-Sync **On**, Black Boost,
   DFR), System Settings (Refresh Rate **Variable**, HDR), the cable
   (USB-C → DisplayPort for VRR) and app settings (Resolve viewer colour
   management, sRGB export).

### Safety

- After a resolution or refresh change, a **"Keep these display settings?"**
  countdown reverts everything after 15 seconds unless you confirm, like
  System Settings does.
- **Undo Last Apply** and **Restore Settings From Before Display Tuner** are
  always available. The saved state lives in
  `~/Library/Application Support/DisplayTuner/` and survives restarts.
- A mirrored screen never takes DDC commands meant for the main monitor.

## Install

Requires macOS 26 or later on Apple Silicon (DDC/CI uses the Apple Silicon
display path).

```bash
cd DisplayTuner
bash make-app.sh --install
```

This explicitly installs and opens **Display Tuner.app**. To build a ZIP without installing, use `bash make-app.sh --package`.
It also adds a menu-bar icon (a dial) for one-click presets across all screens.
CI builds a zipped app on every push (Actions → Display Tuner → artifact
`DisplayTuner`). It's ad-hoc signed, so the first time, right-click → **Open**,
or approve it in System Settings → Privacy & Security.

> [!TIP]
> Switchboard and Display Tuner both talk DDC/CI to the Acer. After Display
> Tuner changes brightness, Switchboard's slider catches up the next time it
> reads the monitor. While editing, keep Switchboard's brightness above the
> monitor's hardware minimum, because below that it dims through the colour
> table, which shifts gamma.

## Using it

1. Pick a screen on the left.
2. Pick what you're doing and how bright the room is.
3. Check the list under **The app will change**, untick anything you don't
   want, and click **Apply**.
4. Work through **Do these yourself**. On the Acer, the important one is
   **Mode → sRGB** for editing and **Mode → Standard** for gaming. It has to
   match the colour profile the app just set.

## The research

Every recommendation links its sources in the app (**Research and sources**).
The main ones:

- Acer XV272K V5 specs: [Acer store](https://store.acer.com/en-in/acer-nitro-xv272k-v5-27-inch-uhd-3840x2160-ips-agile-splendor-gaming-monitor-160hz-refresh-delta-e-1-fhd-320hz-through-dfr-g-sync-freesync-compatible-smart-dial-eyesafe-certified-black), [SHI spec sheet](https://www.shi.com/product/49740911/Acer-Nitro-XV272K-V5bmiiprx)
- Over Drive / Adaptive-Sync behaviour and the sRGB clamp: [Acer Nitro user guide](https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=637376339193437048&Step1=MONITOR&Step2=XV+SERIES&Step3=XV272UV&OS=ALL&LC=en&BC=ACER&SC=PA_6), [DisplayNinja XV272U review](https://www.displayninja.com/acer-xv272u-review/), [Tom's Hardware XV272U review](https://www.tomshardware.com/reviews/acer-nitro-xv272u-kvbmiiprzx-review), [Blur Busters forum](https://forums.blurbusters.com/viewtopic.php?t=11054)
- Variable refresh on Macs: [Apple support 102144](https://support.apple.com/102144)
- HDR400 limits: [RTINGS on DisplayHDR](https://www.rtings.com/monitor/learn/display-hdr), [TFTCentral](https://tftcentral.co.uk/why-your-hdr-monitor-is-probably-not-hdr-at-all-and-why-displayhdr-400-needs-to-go/)
- Editing targets (D65, gamma 2.2, ~120 cd/m², 80–100 for print): [DxO forum](https://forum.dxo.com/t/calibrating-monitor-with-photolab-5-in-mind/33809), [DIYPhotography](https://www.diyphotography.net/monitor-calibration-photography/)
- Video reference (BT.709 / BT.1886): [Apple reference modes](https://support.apple.com/108321)
- ARZOPA: [TechRadar Z1RC review](https://www.techradar.com/pro/arzopa-z1rc-portable-monitor-review), [Mighty Gadget](https://mightygadget.co.uk/arzopa-z1rc-portable-monitor-review-a-2560x1600-hdr-500nits-8bit-qhd-usb-c-hdmi-laptop-monitor)

**Limits of the research.** No independent review of the XV272K **V5**
itself was found, so the menu paths and the Over Drive advice come from Acer's
manuals and reviews of sibling Nitro XV272 models with the same menu system.
Brightness percentages are estimated from the rated 400 cd/m² peak. Only a
colorimeter gives exact figures, and calibrating with one is the only way to
get a reference-grade picture. When you do, the app leaves your calibration
profile alone.

## Adding a monitor

Monitor research lives in `Sources/TunerCore/KnowledgeBase.swift`. Add a
`MonitorProfile` with its specs, menu steps and sources, plus a test in
`Tests/TunerCoreTests/EngineTests.swift`.

## Building and testing

```bash
swift build
swift test     # colour maths, ICC parsing, mode choice, the recommendation engine
```

`TunerCore` (research, colour maths, engine) is plain Foundation and fully
unit-tested. The app target holds the macOS parts: CoreGraphics, ColorSync,
IOKit DDC (from [Switchboard](https://github.com/BireshwarChakravarty/switchboard)),
CoreBrightness, and SwiftUI.
