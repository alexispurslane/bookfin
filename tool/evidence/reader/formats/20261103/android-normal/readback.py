"""Read only this fixture's copied Android records; never edit device state."""

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
marker = json.loads((runtime / 'fixture.json').read_text())
accounts = json.loads((runtime / 'accounts.json').read_text())
account = json.dumps(['http://127.0.0.1:7365', marker['serverId'], accounts['alice']['id']], separators=(',', ':'))


def adb(*arguments):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *arguments])


package = adb('shell', 'pm', 'path', 'dev.bookfin.bookfin').decode().strip().removeprefix('package:')
installed_hash = adb('shell', 'sha256sum', package).decode().split()[0]
snapshot = root / '.cache/normal-acceptance' / case
snapshot.mkdir()
archive = snapshot / 'database.tar'
archive.write_bytes(adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', 'databases', '-cf', '-',
                        'bookfin-personal-records-v1.sqlite', 'bookfin-personal-records-v1.sqlite-wal',
                        'bookfin-personal-records-v1.sqlite-shm'))
with tarfile.open(archive) as source:
    source.extractall(snapshot, filter='data')
database = sqlite3.connect(snapshot / 'bookfin-personal-records-v1.sqlite')
database.row_factory = sqlite3.Row
assert database.execute('pragma integrity_check').fetchone()[0] == 'ok'
output = {'case': case, 'installedApkSha256': installed_hash,
          'source': '4ae8c6c2299e7ec7c16420663a8fc305e87e6c9a',
          'scope': 'Only owned ordinary acceptance account; copied SQLite readback, not timing measurement',
          'sqliteUserVersion': database.execute('pragma user_version').fetchone()[0],
          'integrity': 'ok', 'tables': {}}
for table in ['accounts', 'record_accounts', 'record_actions', 'record_versions', 'record_coverage']:
    rows = [dict(row) for row in database.execute(f'SELECT * FROM {table} WHERE account=?', (account,))]
    for row in rows:
        row['account'] = 'owned-ordinary-account'
        for field in ['payload', 'metadata', 'identities']:
            if field in row:
                original = row[field]
                if field == 'payload':
                    row['payloadSha256'] = hashlib.sha256(original.encode()).hexdigest()
                row[field] = json.loads(original)
                if field == 'payload' and isinstance(row[field], dict) and 'account' in row[field]:
                    row[field]['account'] = 'owned-ordinary-account'
    output['tables'][table] = rows
database.close()
media_directory = 'files/bookfin-media/' + hashlib.sha256(account.encode()).hexdigest()
media_archive = adb('exec-out', 'run-as', 'dev.bookfin.bookfin', 'tar', '-C', media_directory, '-cf', '-', '.')
output['ownedDownloadFiles'] = []
with tarfile.open(fileobj=io.BytesIO(media_archive)) as media:
    for entry in media.getmembers():
        if not entry.isfile():
            continue
        content = media.extractfile(entry).read()
        output['ownedDownloadFiles'].append({'name': entry.name, 'bytes': entry.size,
                                             'sha256': hashlib.sha256(content).hexdigest()})
(Path(__file__).resolve().parent / f'{case}-records.json').write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps({'case': case, 'installedApkSha256': installed_hash,
                  'retainedActions': len(output['tables']['record_actions']),
                  'pendingActions': sum(row['pending'] for row in output['tables']['record_actions']),
                  'legacyAccountRows': len(output['tables']['accounts']), 'integrity': 'ok'}))
