import json
from pathlib import Path


root = Path(__file__).resolve().parent


def read(name):
    return json.loads((root / (name + '.json')).read_text())


baseline = read('baseline')
normal = read('normal-offline-bookmark')
normal_before_offline = read('normal-before-offline')
installed = read('companion-installed')
removed = read('companion-plain-removed')
fresh = read('companion-fresh-plain')
empty = read('downloads-removed')
final = read('final-signed-out')
normal_hash = 'f062456644d1c6e8829b289d130e6047e582eb7fd67b139b1b7263be926615e7'
companion_hash = 'e5bdcd3bacfe9f06233c4f845fa56af54e24d19cd0c0cfce9d2479a5506d44f9'
assert len(baseline['allRetainedPayloadHashes']) == 7
prior = json.loads((root.parent / 'android-normal/all-downloads-removed-records.json').read_text())
assert baseline['allRetainedPayloadHashes'] == sorted(entry['payloadSha256'] for entry in prior['tables']['record_actions'])
assert set(baseline['allRetainedPayloadHashes']) <= set(final['allRetainedPayloadHashes'])
assert normal['installedApkSha256'] == normal_hash
assert normal['allRetainedPayloadHashes'] == installed['allRetainedPayloadHashes']
for capture in [installed, removed, fresh, empty, final]:
    assert capture['installedApkSha256'] == companion_hash
    assert capture['integrity'] == 'ok'
    assert capture['allRetainedPayloadHashes'] == normal['allRetainedPayloadHashes']
assert not empty['ownedFiles']
assert not final['ownedFiles']
for table in ['accounts', 'record_accounts', 'record_actions', 'record_versions', 'record_coverage']:
    assert fresh['tables'][table] == empty['tables'][table]
plain_hash = '42a14c07f1acc6b530dc6fff2b8eadac3a4b08306c2dcee6d8a0558738d39d83'
before_files = {entry['name']: entry for entry in installed['ownedFiles']}
removed_files = {entry['name']: entry for entry in removed['ownedFiles']}
fresh_files = {entry['name']: entry for entry in fresh['ownedFiles']}
reclaimed = [entry for name, entry in before_files.items() if name not in removed_files]
assert any(entry['sha256'] == plain_hash for entry in reclaimed)
assert any('.bookfin-mobi/' + plain_hash in entry['name'] for entry in reclaimed)
assert not any(plain_hash in entry['name'] or entry['sha256'] == plain_hash for entry in removed['ownedFiles'])
assert any(entry['sha256'] == plain_hash for entry in fresh['ownedFiles'])
assert any('.bookfin-mobi/' + plain_hash in entry['name'] for entry in fresh['ownedFiles'])
corpus = read('corpus')
for sample in corpus:
    if sample['title'] == '03 Raven PDF':
        continue
    for capture in [normal_before_offline, fresh]:
        assert any(entry['sha256'] == sample['sha256'] and entry['bytes'] == sample['bytes'] for entry in capture['ownedFiles'])
bookmark_positions = [json.loads(entry['payload']['value']['position']['anchor']) for entry in normal['tables']['record_actions'] if 'bookmarks' in entry['payload']['record']]
assert any(position.get('page') == 5 and position.get('character') == 592 for position in bookmark_positions)
native = read('companion-native-identity')
assert native['installedApkSha256'] == companion_hash
modified = native['libraries'][0]
assert modified['sha256'] == '657b3a35ffa263b42899e48585163e9e5dd32d5c20bf76c4102d3f34516ee56c'
assert modified['replacementMarkerInLibrary'] and modified['executableMappingVerified']
plugin = read('cleanup-plugin-records')
local_hashes = {entry['payloadSha256'] for entry in final['tables']['record_actions']}
server_hashes = {entry['payloadSha256'] for entry in plugin['objects']}
assert server_hashes <= local_hashes
result = {
    'scope': 'Evidence consistency checks, not coverage, mutation testing, a second Android client, or complete acceptance',
    'priorActionsRetainedUnchanged': len(baseline['allRetainedPayloadHashes']),
    'allRetainedActions': len(final['allRetainedPayloadHashes']),
    'ownedRetainedActions': len(final['tables']['record_actions']),
    'ownedPendingActions': sum(entry['pending'] for entry in final['tables']['record_actions']),
    'serverObjectsMatchingLocalPayloads': len(server_hashes),
    'inPlaceReplacementPayloadsUnchanged': True,
    'downloadRemovalPersonalTablesUnchanged': True,
    'plainRemovalBytesReclaimedIncludingManifests': sum(entry['bytes'] for entry in reclaimed),
    'plainRemovalFilesReclaimed': reclaimed,
    'freshPlainConversionAfterVerifiedCacheAbsence': True,
    'modifiedLibraryExecutableMappingVerified': True,
    'finalOwnedDownloadBytes': sum(entry['bytes'] for entry in final['ownedFiles']),
    'cleanupReclaimedBytesIncludingManifests': sum(entry['bytes'] for entry in fresh['ownedFiles']),
    'completeDownloadedOriginalsHashVerified': 7,
    'visibleKf8ResumeAndBookmark': 'failed; t2-42og',
    'explicitSyncRetry': 'failed; t2-00a4',
}
(root / 'evidence-checks.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
