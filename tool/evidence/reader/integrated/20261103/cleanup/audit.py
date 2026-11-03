"""Read-only cleanup audit; stores no credentials or private database copy."""
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import tarfile
import tempfile

output = Path(__file__).resolve().parent

def adb(*args):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *args])

prior = json.loads((output.parent / 'android/stop-audit.json').read_text())
expected = {(row['accountSha256'], row['identity']): (row['payloadSha256'], row['pending']) for row in prior['actions']}
archive = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'databases', '-cf', '-', '.')
with tempfile.TemporaryDirectory(prefix='bookfin-cleanup-') as private:
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(private, filter='data')
    db = sqlite3.connect(f'file:{private}/bookfin-personal-records-v1.sqlite?mode=ro', uri=True)
    actual = {(hashlib.sha256(account.encode()).hexdigest(), identity): (hashlib.sha256(payload.encode()).hexdigest(), pending) for account, identity, payload, pending in db.execute('select account, identity, payload, pending from record_actions')}
    integrity = db.execute('pragma integrity_check').fetchone()[0]
    db.close()
assert actual == expected
assert integrity == 'ok'
network = {key: adb('shell', 'settings', 'get', 'global', key).decode().strip() for key in ['airplane_mode_on', 'wifi_on', 'mobile_data']}
assert network == {'airplane_mode_on': '0', 'wifi_on': '1', 'mobile_data': '1'}
audio = adb('shell', 'dumpsys', 'audio').decode()
start = audio.index('- STREAM_MUSIC:')
music = audio[start:start + 240]
assert 'Muted: true' in music
process = subprocess.run(['adb', '-s', 'emulator-5554', 'shell', 'pidof', 'dev.bookfin.bookfin'], capture_output=True, text=True)
assert process.returncode == 1 and not process.stdout.strip()
content = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'files', '-cf', '-', '.')
with tarfile.open(fileobj=io.BytesIO(content)) as files:
    remaining = [entry.name for entry in files.getmembers() if entry.isfile()]
result = {'all69ActionsUnchanged': True, 'retainedActions': len(actual), 'pendingActions': sum(value[1] for value in actual.values()), 'databaseIntegrity': integrity, 'network': network, 'mediaMuted': True, 'appProcessAbsent': True, 'remainingPrivateFileNames': remaining, 'uiEvidence': ['downloads.txt', 'signed-out.txt'], 'scope': 'Cleanup only; no new OCR or sync acceptance.'}
(output / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
