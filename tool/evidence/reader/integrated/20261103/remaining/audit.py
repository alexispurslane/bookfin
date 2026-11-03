import hashlib
import json
from pathlib import Path


OUTPUT = Path(__file__).resolve().parent


def read(name):
    return json.loads((OUTPUT / (name + '.json')).read_text())


def indexed(snapshot):
    return {(row['accountSha256'], row['identity']): row for row in snapshot['actions']}


baseline = indexed(read('baseline'))
assert len(baseline) == 69 and sum(row['pending'] for row in baseline.values()) == 28
checks = []
for name in ['baseline', 'normal-installed', 'during-dense', 'stop-audit', 'final-retained']:
    snapshot = read(name)
    current = indexed(snapshot)
    assert all(current[key] == value for key, value in baseline.items())
    assert snapshot['all69Unchanged'] and snapshot['integrity'] == 'ok' and snapshot['mediaMuted']
    checks.append({'capture': name, 'retained': len(current), 'pending': sum(row['pending'] for row in current.values()), 'all69IdentitiesPayloadsAndPendingFlagsUnchanged': True})
assert indexed(read('normal-installed')) == baseline
during = [row for key, row in indexed(read('during-dense')).items() if key not in baseline]
final = [row for key, row in indexed(read('final-retained')).items() if key not in baseline]
assert len(during) == len(final) == 1 and during[0]['pending'] == 1 and final[0]['pending'] == 0
assert {key: value for key, value in during[0].items() if key != 'pending'} == {key: value for key, value in final[0].items() if key != 'pending'}
server = read('stop-server')
assert len(server['objects']) == 1
assert server['objects'][0]['identity'] == final[0]['identity']
assert server['objects'][0]['payloadSha256'] == final[0]['payloadSha256']
assert server['objects'][0]['action'] == final[0]['action']
assert server['cursor'] >= server['objects'][0]['sequence'] > 0
assert all(item['containerOmitted'] and item['mediaSourcesOmitted'] for item in server['ordinaryOriginals'])
artifact = read('artifact')
assert artifact['normalApkSha256'] == artifact['installedApkSha256'] == '129a9a82a338a2e7b5cf1abd154c729866a328295c241063fabd26e38353c270'
corpus = read('corpus')
assert corpus['pluginSha256'] == '3b0de5ca1df39baf67c786079898b1ee3b0b09d3bdb86d00ece8a7f5731a9105'
files = read('final-retained')['files']
model = './bookfin-ocr-engine/tessdata/eng.traineddata'
assert next(item['sha256'] for item in files if item['name'] == model) == next(item['sha256'] for item in read('baseline')['files'] if item['name'] == model)
originals = [item for item in files if item['name'].endswith('/complete')]
assert sorted(item['sha256'] for item in originals) == sorted(item['sha256'] for item in corpus['files'].values())
assert not any('ocr' in item['name'].lower() and not 'bookfin-ocr-engine' in item['name'] for item in files)
assert read('final-retained')['network'] == {'airplane_mode_on': '1', 'wifi_on': '0', 'mobile_data': '0'}
assert not read('final-retained')['appProcessAbsent']
before = (OUTPUT / 'dense-active-cancel-before.txt').read_text()
assert 'Recognizing English text…' in before and '[button] "Cancel recognition"' in before
assert 'Tapped @e22' in (OUTPUT / 'dense-active-cancel.txt').read_text()
for name in ['dense-canceled', 'cancel-recovery']:
    assert 'Error (COMMAND_FAILED): Android snapshot helper returned insufficient foreground app content' in (OUTPUT / (name + '.txt')).read_text()
events = [json.loads(line) for line in (OUTPUT / 'events.ndjson').read_text().splitlines()]
failure = next(index for index, event in enumerate(events) if event['exit'] != 0)
assert len(events[failure:]) == 2
assert all(event['arguments'] == ['snapshot', '--force-full'] for event in events[failure:])
assert all(event['exit'] == 1 for event in events[failure:])
cleanup = read('cleanup')
assert all(cleanup[name] for name in ['ownedControllerStopped', 'ownedServerStopped', 'ports7364And7365Free', 'ownedReverseRouteRemoved', 'ownedFixtureAndCredentialsRemoved', 'temporaryPrivateDatabaseCopiesRemoved', 'newActionExactlyMatchesRealPlugin', 'deviceCleanupBlockedByRequiredStop'])
assert cleanup['newPendingActions'] == 0 and cleanup['remainingOwnedDownloads'] == 2
assert read('recovery-inventory')['matchingFixtures'] == 0
release = read('binding-release')
assert release['toolCallSucceeded'] and release['shutdown'] is False
result = {'captures': checks, 'newActionPayloadIdentityAndCausalContextMatchRealPlugin': True, 'explicitSyncNowNotTested': True, 'activeRecognitionAndCancelDispatchObserved': True, 'postCancelStateNotInspectable': True, 'cancelDrainRetryAndDepartureNotAccepted': True, 'noOCRPageCacheAtStop': True, 'originalFilesMatchCorpus': True, 'noUICommandAfterFailedSnapshotRetry': True, 'deviceCleanupStillRequired': True, 'evidenceSha256': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(OUTPUT.iterdir()) if path.is_file() and path.name != 'audit.json'}}
(OUTPUT / 'audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: value for key, value in result.items() if key != 'evidenceSha256'}, indent=2))
