#!/usr/bin/env python3
"""Package local resources without depending on Xcode's asset compiler."""
import json
import plistlib
import re
import shutil
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1])
resources = app / 'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
project = (root / 'CleanKeys.xcodeproj/project.pbxproj').read_text()

def setting(name):
    values = set(re.findall(r'\b' + name + r' = ([^;]+);', project))
    if len(values) != 1:
        raise RuntimeError(f'Expected one consistent {name}: {values}')
    return values.pop().strip('"')

info = {
    'CFBundleExecutable': 'CleanKeys',
    'CFBundleIdentifier': setting('PRODUCT_BUNDLE_IDENTIFIER'),
    'CFBundleName': 'CleanKeys',
    'CFBundleDisplayName': 'CleanKeys',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': setting('MARKETING_VERSION'),
    'CFBundleVersion': setting('CURRENT_PROJECT_VERSION'),
    'CFBundleDevelopmentRegion': 'en',
    'CFBundleLocalizations': ['en', 'hu'],
    'CFBundleIconFile': 'AppIcon',
    'LSMinimumSystemVersion': setting('MACOSX_DEPLOYMENT_TARGET'),
    'LSApplicationCategoryType': 'public.app-category.utilities',
    'NSHighResolutionCapable': True,
    'NSPrincipalClass': 'NSApplication',
    'NSHumanReadableCopyright': 'CleanKeys — local, open-source utility',
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
shutil.copy2(root / 'Design/CleanKeysIcon-1024.png', resources / 'CleanKeysLogo.png')
for language in ('en', 'hu'):
    shutil.copytree(root / 'CleanKeys' / (language + '.lproj'), resources / (language + '.lproj'))
shutil.copy2(root / 'LICENSE', resources / 'LICENSE')

# PNG-encoded icon family. Preserve the project's existing artwork at each size.
icons = root / 'CleanKeys/Assets.xcassets/AppIcon.appiconset'
chunks = []
for kind, filename in [
    ('icp4', 'icon_16x16.png'), ('icp5', 'icon_32x32.png'),
    ('icp6', 'icon_32x32@2x.png'), ('ic07', 'icon_128x128.png'),
    ('ic08', 'icon_256x256.png'), ('ic09', 'icon_512x512.png'),
    ('ic10', 'icon_512x512@2x.png'),
]:
    data = (icons / filename).read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise RuntimeError(f'Invalid PNG: {filename}')
    chunks.append(kind.encode() + struct.pack('>I', len(data) + 8) + data)
data = b''.join(chunks)
(resources / 'AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(data) + 8) + data)
