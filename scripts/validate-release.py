#!/usr/bin/env python3
from pathlib import Path
import json, plistlib
root=Path(__file__).resolve().parents[1]
metadata=json.loads((root/'release.json').read_text())
plist=plistlib.loads((root/'DisplayTuner/Resources/Info.plist').read_bytes())
assert metadata['version'] == plist['CFBundleShortVersionString'] == '2.0.0'
assert metadata['tag'] == 'v2.0.0'
assert (root/'RELEASE_NOTES.md').exists()
assert (root/'DisplayTuner/Resources/AppIcon.base64').exists()
print('Release metadata matches the app bundle')
