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
    sleep 10
    if kill -0 "$pid" 2>/dev/null; then
        # Still running: sample the main thread if nothing was captured (a hang).
        [ -f "$OUT/$name.png" ] || { echo "hang? sampling $name"; sample "$pid" 2 2>/dev/null | head -60; }
        kill "$pid" 2>/dev/null
    else
        echo "exited early: $name"
        latest=$(ls -t ~/Library/Logs/DiagnosticReports/DisplayTuner* 2>/dev/null | head -1)
        [ -n "$latest" ] && head -80 "$latest"
    fi
    wait "$pid" 2>/dev/null
    [ -f "$OUT/$name.png" ] && echo "captured $name" || echo "missing $name"
}
# Warm-up: the first launches on a fresh runner don't always open a window.
for _ in 1 2; do "$BIN" --demo & warm=$!; sleep 10; kill "$warm" 2>/dev/null; wait "$warm" 2>/dev/null; done
shoot patterns dark --patterns
shoot presets dark --presets
shoot activity dark --activity
shoot display-dark dark
shoot display-light light
shoot display-photo-light light --usecase photoEditing
defaults delete app.displaytuner.DisplayTuner appearance 2>/dev/null || true
# Small previews in the log, for reviewers without artifact access.
for f in "$OUT"/*.png; do
    sips -Z 900 -s format jpeg -s formatOptions 55 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 || continue
    echo "::group::preview $(basename "${f%.png}")"
    base64 -i "${f%.png}.jpg" | tr -d '\n'; echo
    echo "::endgroup::"
done
