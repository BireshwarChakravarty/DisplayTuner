> **Version 1.2:** See the [main README](../README.md) for features, install and release instructions.

# Display Tuner

A Mac app for one monitor, the **Acer Nitro XV272K V5**, on an Apple Silicon
Mac. Pick what you're doing (**Competitive Gaming**, **Immersive Gaming**,
**Photo Editing**, **Video Editing**, **MacBook Look**, **Max Brightness** or
**Everyday**), review what will change, and apply it. Other screens, such as a
mirrored portable monitor, are listed but never touched.

## How the research was checked

Every fact, menu path and default in the app was read in a primary source,
and each one links to it in the app (ⓘ → Confirmed Facts):

- **Acer's manuals**, from global-download.acer.com. Acer's manual for the V5
  itself couldn't be downloaded, so menu paths follow the
  [2024 XV275K manual](https://global-download.acer.com/GDFiles/Document/User%20Manual/User%20Manual_Acer_1.0_A_A.pdf?acerid=638769326554563998&Step1=&Step2=&Step3=XV275KP5&OS=ALL&LC=en&BC=ACER&SC=PA_6),
  the closest model with the V5's 4K 160 Hz / 1080p 320 Hz switch (DFR).
  Older XV272 manuals name some items differently.
- **VESA:** the [DisplayHDR certified list](https://displayhdr.org/certified-products/)
  names the XV272K V5 under DisplayHDR 400.
- **Instrumented reviews.** No measured review of the V5 exists yet, so
  measurements come from its siblings and always name the model: the XV272K V3
  ([Danawa/CoolEnjoy](https://dpg.danawa.com/news/view?boardSeq=62&listSeq=5612150)),
  XV282K KV ([PCMonitors](https://pcmonitors.info/reviews/acer-xv282k-kv/)),
  XV273K ([TFTCentral](https://tftcentral.co.uk/reviews/acer_nitro_xv273k.htm))
  and XV272U KV ([Tom's Hardware](https://www.tomshardware.com/reviews/acer-nitro-xv272u-kvbmiiprzx-review)).
- **Apple's support pages** for Adaptive-Sync, HDR, refresh rate and frame
  rate, Night Shift and the MacBook Air's display.

Claims that couldn't be confirmed were removed.

## What it changes, and what it doesn't

| Setting | How | When |
|---|---|---|
| Resolution & refresh rate | CoreGraphics, from the modes macOS lists for the monitor. Applied for this session only until you click **Keep** (a 15-second countdown reverts it otherwise). | Every preset picks the highest rate at your current size; Video Editing picks one that divides evenly by 24/25/30 fps, as Apple advises. |
| Colour profile | ColorSync: sRGB for editing (paired with **Color Space → sRGB** on the monitor), the display's own profile otherwise. A calibration profile you made is never touched. | Editing / everything else |
| Brightness | DDC/CI, to 100%, read back to check. | Max Brightness and MacBook Look only |
| Night Shift | Off, because it shifts colours warmer. Undo turns it back on. | Editing and MacBook Look |

The app never estimates brightness in cd/m². The V5's brightness curve isn't
published, and its sibling the XV272K V3 measured 40.1 cd/m² at Brightness 0
and 388.7 at 100, so a percentage can't be turned into cd/m². Editing presets
explain the common targets instead: about 120 cd/m² for editing (Canon),
80–120 for print work, and 80 for the sRGB reference (W3C). A colorimeter
gives the exact setting.

### The monitor menu

Only the monitor's own buttons can change these, so the app lists them as a
checklist. Paths are from Acer's XV275K manual:

| Setting | Value | Path |
|---|---|---|
| Color Space | General (native colour) / sRGB (editing) | Menu → Color → Color Space |
| Modes | Standard (factory default) | Menu → Color → Modes |
| Max Brightness | On for bright presets (Off by default "to save energy") | Menu → Picture → Max Brightness |
| ACM (dynamic contrast) | Off (factory default) | Menu → Picture → ACM |
| Black Boost | 0 | Menu → Picture → Black Boost |
| HDR | Off for standard content | Menu → Picture → HDR |
| Gamma | 2.2 (factory default) | Menu → Color → Gamma |
| Color Temp. | Warm (factory default) | Menu → Color → Color Temp. |
| Over Drive | Normal | Menu → Gaming → Over Drive |
| Variable Refresh Rate | On | Menu → Gaming → Variable Refresh Rate |
| Max Refresh Rate | 160Hz | Menu → System → Max Refresh Rate |
| DSC | On (factory default) | Menu → System → DSC |
| DDC/CI | On | Menu → System → DDC/CI |

The Max Brightness switch matters most for bright presets: on the XV282K,
Brightness 100 gave 139 cd/m² with it Off and 280 with it On.

## Safety

- **Only brightness and contrast are ever written over DDC/CI.** These are
  controls Acer documents in the Picture menu. Acer's manual warns: *"Adjust
  only those controls that are covered by the operating instructions, since
  improper adjustment of other controls may result in damage."* The app never
  writes colour presets, factory reset, power, input or save-settings commands.
- **Values are clamped** to the maximum the monitor reports for each control.
- **At least 50 ms between DDC/CI commands**, as ddcutil quotes the DDC/CI
  spec. The live brightness slider sends at most about ten writes a second.
- **Nothing is sent while the display or the Mac sleeps**, or for 3 seconds
  after they wake (MonitorControl does the same), and the monitor is read
  afresh afterwards.
- **The wrong-screen guard fails closed:** vendor, model and serial must match
  before anything is sent, and only the Acer is ever addressed.
- **Undo** and **Restore Settings From Before Display Tuner** are always
  available. Saved state lives in `~/Library/Application Support/DisplayTuner/`.

## Install and build

Requires macOS 26 or later on Apple Silicon.

```bash
cd DisplayTuner
bash make-app.sh --install   # or --package to build a ZIP without installing
swift test                   # the engine, research and safety rules
```

`TunerCore` (research, colour maths, engine) is plain Foundation and fully
unit-tested; tests check that every cited source exists, that no preset writes
a colour preset or contrast, and that other screens get no changes. The app
target holds the macOS parts: CoreGraphics, ColorSync, IOKit DDC (from
[Switchboard](https://github.com/BireshwarChakravarty/switchboard)),
CoreBrightness and SwiftUI.
