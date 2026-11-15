#!/usr/bin/env python3
"""Generate the compatibility table from executed evidence, never inferred results."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
evidence = root / 'docs/evidence/ANDROID_API_29_37'
rows = ['## Executed emulator matrix', '', '| API | Image | ADB checks | System UI checks | Result |', '|---|---|---|---|---|']
for api in range(29, 38):
    image = 'Google Play ARM64' if api == 31 else 'Google APIs ARM64' if api in (29, 30, 34, 35) else 'AOSP ARM64'
    file = evidence / f'api-{api}/results.json'
    if not file.exists():
        rows.append(f'| {api} | {image} | NOT TESTED | NOT TESTED | NOT TESTED |')
        continue
    data = json.loads(file.read_text())
    adb = [x for x in data if x.get('method') == 'adb-screencap']
    system = [x for x in data if x.get('method') == 'System UI KEYCODE_SYSRQ']
    def label(items, expected):
        count = sum(x['status'] == 'PASS' for x in items)
        if len(items) == expected and count == expected:
            return f'PASS ({count}/{expected})'
        return f'{count}/{expected} PASS; ' + ', '.join(sorted({x['status'] for x in items if x['status'] != 'PASS'}) or ['NOT TESTED'])
    status = 'PASS' if len(data) == 25 and all(x['status'] == 'PASS' for x in data) else 'FAIL' if any(x['status'] == 'FAIL' for x in data) else 'BLOCKED'
    rows.append(f'| {api} | {image} | {label(adb, 23)} | {label(system, 2)} | [{status}](evidence/ANDROID_API_29_37/api-{api}/results.json) |')
report = root / 'docs/VERIFICATION.md'
text = report.read_text().split('<!-- MATRIX -->')[0]
report.write_text(text.rstrip() + '\n\n<!-- MATRIX -->\n' + '\n'.join(rows) + '\n')
print('\n'.join(rows))
