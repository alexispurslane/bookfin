import hashlib
import io
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tarfile

root = Path.cwd()
case = sys.argv[1]
if not case.replace('-', '').isalnum():
    raise SystemExit('Use a simple case name')
runtime = root / '.cache/sync/runtime'
private = root / '.cache/corrected-acceptance' / case
private.mkdir()
output = root / 'tool/evidence/reader/formats/20261103/android-corrected'
output.mkdir(parents=True, exist_ok=True)
def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])
package = adb('shell', 'pm', 'path', 'dev.bookfin.bookfin').decode().strip().removeprefix('package:')
installed = adb('exec-out', 'cat', package)
archive = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'databases', '-cf', '-', '.')
with tarfile.open(fileobj=io.BytesIO(archive)) as source:
    source.extractall(private, filter='data')
database = sqlite3.connect(private / 'bookfin-personal-records-v1.sqlite')
database.row_factory = sqlite3.Row
result = {'case': case, 'installedApkSha256': hashlib.sha256(installed).hexdigest(), 'integrity': database.execute('pragma integrity_check').fetchone()[0], 'source': '44d53afbe491f28cec0205584ba7f023ec8a10b6', 'allRetainedPayloadHashes': sorted(hashlib.sha256(row[0].encode()).hexdigest() for row in database.execute('select payload from record_actions')), 'tables': {}}
if (runtime / 'accounts.json').exists():
    marker = json.loads((runtime / 'fixture.json').read_text())
    accounts = json.loads((runtime / 'accounts.json').read_text())
    account = json.dumps(['http://127.0.0.1:7365', marker['serverId'], accounts['alice']['id']], separators=(',', ':'))
    for table in ['accounts', 'record_accounts', 'record_actions', 'record_versions', 'record_coverage']:
        rows = [dict(row) for row in database.execute(f'SELECT * FROM {table} WHERE account=?', (account,))]
        for row in rows:
            row['account'] = 'owned-corrected-format-account'
            for field in ['payload', 'metadata', 'identities']:
                if field in row:
                    if field == 'payload': row['payloadSha256'] = hashlib.sha256(row[field].encode()).hexdigest()
                    row[field] = json.loads(row[field])
                    if isinstance(row[field], dict) and 'account' in row[field]: row[field]['account'] = 'owned-corrected-format-account'
        result['tables'][table] = rows
    media = 'files/bookfin-media/' + hashlib.sha256(account.encode()).hexdigest()
    content = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', media, '-cf', '-', '.')
    result['ownedFiles'] = []
    try:
        with tarfile.open(fileobj=io.BytesIO(content)) as files:
            for entry in files.getmembers():
                if entry.isfile():
                    data = files.extractfile(entry).read()
                    result['ownedFiles'].append({'name': entry.name, 'bytes': entry.size, 'sha256': hashlib.sha256(data).hexdigest()})
    except tarfile.ReadError:
        result['ownedFilesUnavailable'] = True
database.close()
(output / (case + '.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'case': case, 'apk': result['installedApkSha256'], 'allRetainedActions': len(result['allRetainedPayloadHashes']), 'ownedActions': len(result['tables'].get('record_actions', [])), 'integrity': result['integrity']}))
