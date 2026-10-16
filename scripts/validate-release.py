#!/usr/bin/env python3
from pathlib import Path
import json, plistlib, re
root=Path(__file__).resolve().parents[1]
metadata=json.loads((root/'release.json').read_text())
plist=plistlib.loads((root/'DisplayTuner/Resources/Info.plist').read_bytes())
assert metadata['version'] == plist['CFBundleShortVersionString']
assert re.fullmatch(r'\d+\.\d+\.\d+', metadata['version'])
assert metadata['tag'] == 'v' + metadata['version']
assert (root/'RELEASE_NOTES.md').exists()
assert (root/'DisplayTuner/Resources/AppIcon.base64').exists()
print('Release metadata matches the app bundle')
