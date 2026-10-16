#!/bin/bash
# Capture the app window in its demo workspace (simulated displays, no
# hardware access) for design review. Usage: screenshots.sh <app> <out-dir>
set -uo pipefail
APP="$1"; OUT="$2"
BIN="$APP/Contents/MacOS/DisplayTuner"
mkdir -p "$OUT"
shoot() {
    local name="$1" appearance="$2"; shift 2
    defaults write app.displaytuner.DisplayTuner appearance "$appearance"
    "$BIN" --demo "$@" --screenshot "$PWD/$OUT/$name.png" &
    local pid=$!
    sleep 8
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    [ -f "$OUT/$name.png" ] && echo "captured $name" || echo "missing $name"
}
shoot overview-dark dark
shoot overview-light light
shoot finetune-dark dark --controls
shoot research-dark dark --research
shoot presets-dark dark --presets
shoot patterns-dark dark --patterns
shoot activity-dark dark --activity
defaults delete app.displaytuner.DisplayTuner appearance 2>/dev/null || true
# Small previews in the log, for reviewers without artifact access.
for f in "$OUT"/*.png; do
    sips -Z 900 -s format jpeg -s formatOptions 55 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 || continue
    echo "::group::preview $(basename "${f%.png}")"
    base64 -i "${f%.png}.jpg" | tr -d '\n'; echo
    echo "::endgroup::"
done
