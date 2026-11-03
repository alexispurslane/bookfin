import json
from pathlib import Path

root = Path(__file__).resolve().parent


def load(case):
    return json.loads((root / f'{case}.json').read_text())


def actions(case):
    return {row['identity']: row for row in load(case)['actions']}


def cache_files(case, owner=None):
    return {entry['name']: entry for entry in load(case)['files']
            if '/.bookfin-ocr/' in entry['name']
            and (owner is None or f'/{owner}/' in entry['name'])}


def exact_remote(local_case, server_case, owner=None):
    local = actions(local_case)
    if owner:
        local = {identity: row for identity, row in local.items() if row['accountSha256'] == owner}
    remote = {row['identity']: row for row in load(server_case)['objects']}
    assert set(local) == set(remote)
    for identity, row in local.items():
        assert row['pending'] == 0
        assert row['payloadSha256'] == remote[identity]['payloadSha256']
        assert row['action'] == remote[identity]['action']
    assert load(server_case)['serverVersion'] == '12.4.0'
    return len(local)


before = load('before-first-ocr')
artifact = load('artifact')
hashes = (root / 'artifact-hashes.txt').read_text()
assert all(artifact[key] in hashes for key in ('apkSha256', 'sourceArchiveSha256', 'pluginSha256'))
assert (root / 'installed-hash.txt').read_text().split()[0] == artifact['apkSha256']
assert 'No such file or directory' in (root / 'preinstall.txt').read_text()
assert 'package:dev.bookfin.bookfin' not in (root / 'preinstall.txt').read_text()
assert (root / 'install.txt').read_text().strip() == 'Performing Streamed Install\nSuccess'
assert load('host-cleanup')['ownedProcessesStopped']
assert load('device-final')['ownedAvdBooted'] is False
assert load('device-final')['threadOpenDevices'] == []
assert load('secret-scan')['matchingFiles'] == []
assert before['actions'] == []
assert all('traineddata' not in entry['name'] and '/.bookfin-ocr/' not in entry['name'] for entry in before['files'])
assert before['network'] == {'airplane_mode_on': '1', 'wifi_on': '0', 'mobile_data': '0'}
assert (root / 'offline-routes.txt').read_text().strip() == ''
assert load('bundled-model')[0]['sha256'] == '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2'
pending = actions('unicode-pending')
assert len(pending) == 5 and all(row['pending'] == 1 for row in pending.values())
assert actions('disconnected-closed') == pending == actions('disconnected-relaunched')
assert load('disconnected-closed')['appProcessAbsent']
assert cache_files('first-ocr-active') == cache_files('cache-reused')
assert 'The quiet garden' in (root / 'reflow.txt').read_text()
assert 'Source page 1: The quiet garden' in (root / 'search-results-complete.txt').read_text()
assert 'No English text was recognized. Read the original page.' in (root / 'genuine-blank-complete.txt').read_text()
bookmark = next(row['action']['value'] for row in pending.values() if row['action']['value'].get('title'))
assert bookmark['title'] == 'Fresh “Café” 中文 🐟'
assert bookmark['note'] == 'Déjà vu — ‘naïve’ 中文 🐟'
assert json.loads(bookmark['position']['anchor'])['character'] == 611
assert load('all-offline-server')['objects'] == []
alice_count = exact_remote('explicit-synced', 'explicit-server')
assert alice_count == 8
assert actions('repeated-synced') == actions('explicit-synced') == actions('synced-restarted')
assert load('repeated-server')['objects'] == load('explicit-server')['objects']
for identity, row in actions('all-offline-pending').items():
    assert {**row, 'pending': 0} == actions('explicit-synced')[identity]
for case in ('explicit', 'bob-explicit'):
    timing = load(f'{case}-timing')
    assert 0 < timing['routeRestoredUnix'] - timing['launchStartedUnix'] < 30
    assert timing['routeRestoredUnix'] < timing['buttonCommandStartedUnix']
    assert timing['buttonCommandCompletedUnix'] - timing['launchStartedUnix'] < 30
alice = next(iter(pending.values()))['accountSha256']
bob_rows = [row for row in load('bob-cache')['actions'] if row['accountSha256'] != alice]
assert len(bob_rows) == 1 and bob_rows[0]['pending'] == 1
bob = bob_rows[0]['accountSha256']
assert not cache_files('bob-downloaded-before-ocr', bob)
assert len(cache_files('bob-cache', bob)) == 1
assert cache_files('bob-cache', alice) == cache_files('bob-before-download', alice)
assert not cache_files('bob-removed', bob)
assert cache_files('bob-removed', alice) == cache_files('bob-cache', alice)
assert 'No reading bookmarks in this edition.' in (root / 'bob-bookmarks-after.txt').read_text()
assert 'Fresh “Café” 中文 🐟' in (root / 'alice-return-bookmarks-after.txt').read_text()
assert exact_remote('bob-synced', 'bob-server-after', bob) == 1
final = load('final-retained')
assert all(row['pending'] == 0 for row in final['actions'])
assert final['appProcessAbsent'] and final['mediaMuted'] and final['integrity'] == 'ok'
assert final['network'] == {'airplane_mode_on': '0', 'wifi_on': '1', 'mobile_data': '1'}
assert not any('bookfin-media/' in entry['name'] for entry in final['files'])
assert not (root / 'final-routes.txt').read_text().strip()
for identity, row in actions('explicit-synced').items():
    assert actions('final-retained')[identity] == row
final_alice_count = exact_remote('final-retained', 'final-alice-server', alice)
final_bob_count = exact_remote('final-retained', 'final-bob-server', bob)
assert len(final['actions']) == final_alice_count + final_bob_count
result = {'firstOfflineOcr': True, 'durableUnicodePending': 5, 'explicitAliceUploads': alice_count,
          'crossAccountOwnership': True, 'finalAcknowledgedActions': len(final['actions']),
          'finalPending': 0, 'integrity': 'ok', 'cleanup': 'downloads removed, signed out, app closed, routes absent, radios restored, media muted'}
(root / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
