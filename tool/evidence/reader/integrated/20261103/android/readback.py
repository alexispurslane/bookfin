import hashlib
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent
PRIVATE = ROOT / '.cache/combined-acceptance'
CASE = sys.argv[1]
if not CASE.replace('-', '').isalnum():
    raise SystemExit('Use a simple evidence name')
os.umask(0o077)
capture = PRIVATE / CASE
capture.mkdir(parents=True)


def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])


def digest(value):
    return hashlib.sha256(value).hexdigest()


package = adb('shell', 'pm', 'path', 'dev.bookfin.bookfin').decode().strip().removeprefix('package:')
installed = adb('exec-out', 'cat', package)
(capture / 'installed.apk').write_bytes(installed)
archive = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'databases', '-cf', '-', '.')
with tarfile.open(fileobj=io.BytesIO(archive)) as source:
    source.extractall(capture, filter='data')
database = sqlite3.connect(f'file:{capture}/bookfin-personal-records-v1.sqlite?mode=ro', uri=True)
database.row_factory = sqlite3.Row
actions = []
for row in database.execute('select account, identity, payload, pending from record_actions order by account, identity'):
    action = json.loads(row['payload'])
    action['account'] = digest(row['account'].encode())
    actions.append({'accountSha256': digest(row['account'].encode()), 'identity': row['identity'],
                    'payloadSha256': digest(row['payload'].encode()), 'pending': row['pending'], 'action': action})
result = {'case': CASE, 'installedApkSha256': digest(installed),
          'integrity': database.execute('pragma integrity_check').fetchone()[0], 'actions': actions}
database.close()
content = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'files', '-cf', '-', '.')
result['files'] = []
with tarfile.open(fileobj=io.BytesIO(content)) as files:
    for entry in files.getmembers():
        if entry.isfile():
            data = files.extractfile(entry).read()
            result['files'].append({'name': entry.name, 'bytes': entry.size, 'sha256': digest(data), 'modifiedUnixSeconds': entry.mtime})
            if 'ocr' in entry.name.lower() or entry.name.endswith('.json'):
                saved = capture / 'files' / entry.name
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_bytes(data)
result['audio'] = adb('shell', 'dumpsys', 'audio').decode()
start = result['audio'].find('- STREAM_MUSIC:')
result['audio'] = result['audio'][start:start + 240]
result['network'] = {name: adb('shell', 'settings', 'get', 'global', name).decode().strip()
                     for name in ['airplane_mode_on', 'wifi_on', 'mobile_data']}
(OUTPUT / f'{CASE}.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'case': CASE, 'apkSha256': result['installedApkSha256'], 'retained': len(actions),
                  'pending': sum(action['pending'] for action in actions), 'files': len(result['files']),
                  'integrity': result['integrity'], 'musicMuted': 'Muted: true' in result['audio']}))
