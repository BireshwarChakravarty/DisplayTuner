#!/usr/bin/env python3
"""Materialize the versioned icon source and build an ICNS without external dependencies."""
from pathlib import Path
import base64, hashlib, struct, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
resources = root/'DisplayTuner/Resources'
encoded = resources/'AppIcon.base64'
if encoded.exists():
    data = base64.b64decode(encoded.read_text(), validate=False)
    (resources/'AppIcon.png').write_bytes(data)
source = resources/'AppIcon.png'
if not source.exists(): raise SystemExit('Missing icon source')
blocks = []
with tempfile.TemporaryDirectory(prefix='displaytuner-icons-') as directory:
    for size, kind in [(16,'icp4'),(32,'icp5'),(64,'icp6'),(128,'ic07'),(256,'ic08'),(512,'ic09'),(1024,'ic10')]:
        output = Path(directory)/f'{size}.png'
        subprocess.run(['sips','-z',str(size),str(size),str(source),'--out',str(output)],check=True,stdout=subprocess.DEVNULL)
        png = output.read_bytes()
        blocks.append(kind.encode()+struct.pack('>I',len(png)+8)+png)
body = b''.join(blocks)
(resources/'AppIcon.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
print('App icon built (16–1024 px)')
