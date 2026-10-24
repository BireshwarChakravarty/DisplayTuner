#!/usr/bin/env python3
"""Check that the release metadata, the app bundle and the docs agree before
anything is published. Runs in CI on every push."""
from pathlib import Path
import json, plistlib, re, sys

root = Path(__file__).resolve().parents[1]
errors = []

def check(condition, message):
    if not condition:
        errors.append(message)

metadata = json.loads((root / 'release.json').read_text())
plist = plistlib.loads((root / 'DisplayTuner/Resources/Info.plist').read_bytes())
version = metadata.get('version', '')
short = '.'.join(version.split('.')[:2])

check(re.fullmatch(r'\d+\.\d+\.\d+', version), f'release.json version {version!r} is not x.y.z')
check(metadata.get('tag') == f'v{version}', f'release.json tag should be v{version}')
check(plist.get('CFBundleShortVersionString') == version, 'Info.plist version differs from release.json')
check(str(plist.get('CFBundleVersion', '')).isdigit(), 'Info.plist build number must be numeric')
name = plist.get('CFBundleName', '')
check(metadata.get('name') == f'{name} {short}', f'release.json name should be "{name} {short}"')

notes = (root / 'RELEASE_NOTES.md').read_text()
check(notes.splitlines()[0] == f'# {name} {short}', f'RELEASE_NOTES.md must start with "# {name} {short}"')
check(f'GamutPro-{version}-macOS.zip' in notes, f'RELEASE_NOTES.md must name GamutPro-{version}-macOS.zip')
readme = (root / 'README.md').read_text()
check(f'Download {name} {short}' in readme, f'README.md must link "Download {name} {short}"')
check((root / 'DisplayTuner/Resources/AppIcon.base64').exists(), 'AppIcon.base64 is missing')

if errors:
    for error in errors:
        print(f'error: {error}', file=sys.stderr)
    sys.exit(1)
print('Release metadata, app bundle and docs agree')
