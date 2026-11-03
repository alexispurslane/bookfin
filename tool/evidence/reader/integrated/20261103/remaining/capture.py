import hashlib
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time


OUTPUT = Path(__file__).resolve().parent
CASE = sys.argv[1]
assert CASE.replace('-', '').isalnum()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])


archive = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'databases', '-cf', '-', '.')
with tempfile.TemporaryDirectory(prefix='bookfin-remaining-') as private:
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(private, filter='data')
    database = sqlite3.connect(f'file:{private}/bookfin-personal-records-v1.sqlite?mode=ro', uri=True)
    actions = []
    for account, identity, payload, pending in database.execute('select account, identity, payload, pending from record_actions order by account, identity'):
        action = json.loads(payload)
        action['account'] = digest(account.encode())
        actions.append({'accountSha256': digest(account.encode()), 'identity': identity, 'payloadSha256': digest(payload.encode()), 'pending': pending, 'action': action})
    integrity = database.execute('pragma integrity_check').fetchone()[0]
    database.close()
baseline = json.loads((OUTPUT.parent / 'android/stop-audit.json').read_text())['actions']
expected = {(row['accountSha256'], row['identity']): row for row in baseline}
actual = {(row['accountSha256'], row['identity']): row for row in actions}
assert all(actual[key] == value for key, value in expected.items())
assert integrity == 'ok'
content = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'files', '-cf', '-', '.')
inventory = []
with tarfile.open(fileobj=io.BytesIO(content)) as files:
    for entry in files.getmembers():
        if entry.isfile():
            data = files.extractfile(entry).read()
            inventory.append({'name': entry.name, 'bytes': len(data), 'sha256': digest(data), 'modified': entry.mtime})
audio = adb('shell', 'dumpsys', 'audio').decode()
start = audio.index('- STREAM_MUSIC:')
music = audio[start:start + 240]
assert 'Muted: true' in music
network = {key: adb('shell', 'settings', 'get', 'global', key).decode().strip() for key in ['airplane_mode_on', 'wifi_on', 'mobile_data']}
process = subprocess.run(['adb', '-s', 'emulator-5554', 'shell', 'pidof', 'dev.bookfin.bookfin'], capture_output=True, text=True)
result = {'case': CASE, 'timeUnix': time.time(), 'all69Unchanged': True, 'integrity': integrity, 'actions': actions, 'files': inventory, 'mediaMuted': True, 'network': network, 'appProcessAbsent': not process.stdout.strip()}
(OUTPUT / f'{CASE}.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({'case': CASE, 'retained': len(actions), 'pending': sum(row['pending'] for row in actions), 'original69Unchanged': True, 'files': len(inventory), 'appAbsent': result['appProcessAbsent']}))
