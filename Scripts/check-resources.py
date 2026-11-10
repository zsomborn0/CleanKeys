#!/usr/bin/env python3
"""Check translated key/format coverage and Xcode source registration."""
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent

def read_strings(path):
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))

en = read_strings(root / 'CleanKeys/en.lproj/Localizable.strings')
hu = read_strings(root / 'CleanKeys/hu.lproj/Localizable.strings')
assert en.keys() == hu.keys(), 'Translation key mismatch'
for key in en:
    assert en[key] and hu[key], f'Empty translation: {key}'
    assert re.findall(r'%[a-z@]', en[key]) == re.findall(r'%[a-z@]', hu[key]), key
project = (root / 'CleanKeys.xcodeproj/project.pbxproj').read_text()
for source in (root / 'CleanKeys').glob('*.swift'):
    assert f'{source.name} in Sources' in project, f'Unregistered Xcode source: {source.name}'
    for key in re.findall(r'L10n\.(?:text|format)\("([^"\\]+)"', source.read_text()):
        assert key in en, f'Missing translation: {key}'
subprocess.run(['plutil', '-lint', str(root / 'CleanKeys.xcodeproj/project.pbxproj')], check=True)
print(f'Resources verified: {len(en)} English/Hungarian entries and all Swift source registrations.')
