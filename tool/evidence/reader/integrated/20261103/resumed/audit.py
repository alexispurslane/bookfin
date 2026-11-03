import json
from pathlib import Path

output = Path(__file__).resolve().parent


def read(name):
    return json.loads((output / (name + '.json')).read_text())


def actions(snapshot):
    return {(row['accountSha256'], row['identity']): row for row in snapshot['actions']}


def caches(snapshot):
    return {item['name']: item for item in snapshot['files'] if '/.bookfin-ocr/' in item['name']}


baseline = actions(read('baseline'))
assert len(baseline) == 70
assert sum(row['pending'] for row in baseline.values()) == 28
captures = []
for path in sorted(output.glob('*.json')):
    value = json.loads(path.read_text())
    if isinstance(value, dict) and 'actions' in value:
        actual = actions(value)
        assert all(actual[key] == row for key, row in baseline.items()), path.name
        assert value['integrity'] == 'ok' and value['mediaMuted'], path.name
        captures.append(path.name)
before = actions(read('unicode-sync-before'))
after = actions(read('unicode-sync-after'))
new = {key: row for key, row in before.items() if key not in baseline}
assert len(new) == 5 and all(row['pending'] == 1 for row in new.values())
assert read('unicode-sync-server-before')['objects'] == []
remote = {row['identity']: row for row in read('unicode-sync-server-after')['objects']}
assert len(remote) == len(new)
for key, row in new.items():
    assert after[key] == {**row, 'pending': 0}
    assert remote[key[1]]['payloadSha256'] == row['payloadSha256']
    assert remote[key[1]]['action'] == row['action']
    assert remote[key[1]]['sequence'] > 0
assert any(row['action'].get('value', {}).get('title') == '“Café” 中文 🐟' and row['action']['value']['note'] == 'Déjà vu — ‘naïve’ 中文 🐟' for row in new.values())
events = [json.loads(line) for line in (output / 'events.ndjson').read_text().splitlines()]
timing = read('unicode-sync-timing')
button = next(event for event in events if event['evidence'] == 'unicode-sync-button.txt')
assert timing['routeRestored'] < button['start'] < timing['relaunchStart'] + 30
assert (output / 'route-off.txt').read_text().strip() == ''
assert read('disconnected')['network'] == {'airplane_mode_on': '1', 'wifi_on': '0', 'mobile_data': '0'}
for case in ['dense-active-cancel', 'single-cancel', 'nonzero-cancel-retry']:
    assert 'Recognizing English text…' in (output / (case + '-before.txt')).read_text()
    assert 'Recognition canceled.' in (output / (case + '-after.txt')).read_text()
for case in ['active-departure', 'single-active-departure']:
    assert 'Recognizing English text…' in (output / (case + '-before.txt')).read_text()
    assert 'Book details' in (output / (case + '-after.txt')).read_text()
assert 'No English text was recognized.' in (output / 'blank-fallback-observed.txt').read_text()
assert 'Original source page 1' in (output / 'blank-original-after.txt').read_text()
assert 'The quiet garden A reader opened the book' in (output / 'single-reflow-after.txt').read_text()
cached = caches(read('single-bookmarked'))
assert len(cached) == 1 and caches(read('single-cache-reused')) == cached
assert not caches(read('single-removal-complete'))
originals = {item['name']: item for item in read('disconnected')['files'] if item['name'].endswith('/complete')}
removed_originals = {item['name']: item for item in read('single-removal-complete')['files'] if item['name'].endswith('/complete')}
assert originals == removed_originals
assert not caches(read('nonzero-fallback'))
assert caches(read('single-departure-late')) == caches(read('single-departure'))
saved = actions(read('single-bookmarked'))
fallback = actions(read('nonzero-fallback'))
nonzero = []
for key, row in saved.items():
    if key in baseline:
        continue
    value = row['action'].get('value') or {}
    position = value.get('position', value)
    anchor = json.loads(position['anchor']) if position.get('anchor') else {}
    if anchor.get('character') == 574:
        assert fallback[key]['payloadSha256'] == row['payloadSha256']
        assert fallback[key]['action'] == row['action']
        nonzero.append(json.loads(row['action']['record'])[1])
assert set(nonzero) == {'resumes', 'bookmarks'}
final = read('final-retained')
final_actions = actions(final)
final_new = {key: row for key, row in final_actions.items() if key not in baseline}
remote_final = {row['identity']: row for row in read('final-server')['objects']}
assert len(remote_final) == len(final_new)
for key, row in final_new.items():
    assert row['pending'] == 0
    assert remote_final[key[1]]['payloadSha256'] == row['payloadSha256']
    assert remote_final[key[1]]['action'] == row['action']
assert final['appProcessAbsent'] and final['network'] == {'airplane_mode_on': '0', 'wifi_on': '1', 'mobile_data': '1'}
assert not any('/bookfin-media/' in item['name'] for item in final['files'])
assert read('artifact')['apkSha256'] == '8b31c7448f746226453d4677f944c9ba4f5668f657bba8015f94973372744e09'
cleanup = read('host-cleanup')
assert cleanup['ownedProcessesAbsent'] and cleanup['ownedPortsFree'] and cleanup['ownedRouteAbsent'] and cleanup['ownedPrivateFixtureRemoved']
release = read('binding-release')
assert release['shutdown'] is False and release['deviceId'] == 'emulator-5554' and release['furtherDeviceActions'] is False
result = {'allOriginal70Unchanged': True, 'original28StillPending': True, 'retainedActions': len(final_actions), 'newAccountAcknowledgedActions': len(final_new), 'explicitSyncAcknowledgedUnicodeActions': len(new), 'snapshotsAudited': captures, 'nonzeroCharacterPreserved': 574, 'cachedReopenAndOrdinaryRemoval': True, 'nativeDrainOrdering': 'Not independently measured on Android', 'lateResultScope': 'Active status immediately before departure; details and cache stable after departure. One cache appeared during the departure command, so return-before-disposal versus late publication is not distinguished.', 'deviceCleanup': 'Passed before shutdown:false release', 'newDefect': 't8-oitu'}
(output / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
