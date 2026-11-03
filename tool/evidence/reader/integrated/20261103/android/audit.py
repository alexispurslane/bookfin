import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import zipfile


ROOT = Path.cwd()
OUTPUT = Path(__file__).resolve().parent


def read(name):
    return json.loads((OUTPUT / (name + '.json')).read_text())


def identities(snapshot):
    return {(item['accountSha256'], item['identity']): item for item in snapshot['actions']}


baseline = read('baseline')
original = identities(baseline)
assert len(original) == 44 and sum(item['pending'] for item in original.values()) == 28
checks = []
for path in sorted(OUTPUT.glob('*.json')):
    snapshot = json.loads(path.read_text())
    if not isinstance(snapshot, dict) or 'actions' not in snapshot:
        continue
    current = identities(snapshot)
    assert all(current[key] == value for key, value in original.items()), path.name
    assert snapshot['integrity'] == 'ok' and 'Muted: true' in snapshot['audio'], path.name
    checks.append({'case': snapshot['case'], 'retained': len(current), 'original44Unchanged': True,
                   'originalPending': sum(current[key]['pending'] for key in original)})
assert identities(read('before-companion')) == identities(read('companion-installed'))
assert len(identities(read('before-companion'))) == 69
final = read('stop-audit')
owned = {key: value for key, value in identities(final).items() if key not in original}
assert len(owned) == 25 and sum(item['pending'] for item in owned.values()) == 0
server = read('stop-audit-server')
assert len(server['objects']) == len(owned)
assert sorted(item['payloadSha256'] for item in owned.values()) == sorted(item['payloadSha256'] for item in server['objects'])
local_actions = {(item['action']['replica'], item['action']['sequence']): item['action'] for item in owned.values()}
for item in server['objects']:
    action = item['action']
    assert local_actions[(action['replica'], action['sequence'])] == action
unicode_actions = [item for item in owned.values() if any(ord(character) > 127 for character in json.dumps(item['action']['value'], ensure_ascii=False))]
title_actions = [item for item in owned.values() if '“Café 中文”' in json.dumps(item['action']['value'], ensure_ascii=False)]
assert title_actions
for item in title_actions:
    assert '“déjà vu”, 中文, 🐟.' in json.dumps(item['action']['value'], ensure_ascii=False)
normal = read('normal-installed')
artifact = Path('/Users/alexispurslane/Development/bookfin/.cache/artifacts/bookfin-71af288-combined')
with zipfile.ZipFile(artifact / 'bookfin-71af288-arm64-debug.apk') as normal_apk, zipfile.ZipFile(artifact / 'replacement/bookfin-replacement.apk') as companion_apk:
    normal_names = {name for name in normal_apk.namelist() if not name.startswith('META-INF/')}
    companion_names = {name for name in companion_apk.namelist() if not name.startswith('META-INF/')}
    assert normal_names == companion_names
    changed = sorted(name for name in normal_names if normal_apk.read(name) != companion_apk.read(name))
    assert changed == ['lib/arm64-v8a/libmobi.so']
native = read('companion-native-identity')
assert all(item['executableMappingVerified'] for item in native['libraries'])
assert native['libraries'][0]['replacementMarkerInLibrary']


class Words(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.words = []
        self.parts = None

    def handle_starttag(self, tag, attributes):
        if tag == 'span' and 'ocrx_word' in dict(attributes).get('class', '').split():
            self.parts = []

    def handle_data(self, data):
        if self.parts is not None:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag == 'span' and self.parts is not None:
            self.words.append(''.join(self.parts))
            self.parts = None


def edits(expected, actual):
    previous = list(range(len(actual) + 1))
    for expected_index, expected_value in enumerate(expected, 1):
        current = [expected_index]
        for actual_index, actual_value in enumerate(actual, 1):
            current.append(min(current[-1] + 1, previous[actual_index] + 1,
                               previous[actual_index - 1] + (expected_value != actual_value)))
        previous = current
    return previous[-1]


english = (ROOT / 'test/reader/fixtures/ocr/generated-english.txt').read_text()
historical = (ROOT / 'tool/evidence/reader/ocr/20261102/android-device/inputs/raven-1873-page-9-poem-crop.txt').read_text()
references = {'16027709b0a8b3f79d06d189e5cda463b36b921e34cfc02e965ef33fb521d4a7': ('Generated English', english),
              '545e5843794bc0138fb397412bef477ad33c92935eb5babd1ccfed65ab53c54f': ('Six unchanged English image draws', english * 6),
              'aabcc4e96d10424532ab651369f3f14df60aff086d13178f605e5f731c4a9a55': ('Pinned historical crop', historical)}
scores = []
for cached in read('ocr-cache-readback'):
    content = json.loads(cached['rawCacheJson'])
    parser = Words()
    parser.feed(content['hocr'])
    recognized = ' '.join(parser.words)
    raw = cached['rawCacheJson'].encode()
    entry = {'originalSha256': cached['sourceSha256'], 'recognizedText': recognized,
             'cacheBytes': len(raw), 'cacheSha256': hashlib.sha256(raw).hexdigest()}
    assert any(item['sha256'] == entry['cacheSha256'] and item['bytes'] == len(raw) for item in final['files'])
    if cached['sourceSha256'] in references:
        label, reference = references[cached['sourceSha256']]
        expected_words = reference.split()
        entry.update(label=label, referenceWords=len(expected_words), wordEdits=edits(expected_words, recognized.split()),
                     characterEdits=edits(' '.join(expected_words), recognized),
                     comparison='Unit-cost insertion/deletion/substitution. Whitespace folded. Punctuation and case preserved.')
    scores.append(entry)
(OUTPUT / 'ocr-accuracy.json').write_text(json.dumps(scores, indent=2, ensure_ascii=False) + '\n')
first = read('first-ocr')
before = read('before-first-ocr')
assert not any('bookfin-ocr-engine' in item['name'] for item in before['files'])
model = next(item for item in first['files'] if item['name'].endswith('eng.traineddata'))
assert model['bytes'] == 4113088 and model['sha256'] == '7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2'
first_cache = next(item for item in first['files'] if '.bookfin-ocr/' in item['name'])
for case in ['offline-ocr-restart', 'long-offline-restart', 'stop-audit']:
    cached = next(item for item in read(case)['files'] if item['name'] == first_cache['name'])
    assert cached['sha256'] == first_cache['sha256']
before_files = {item['name']: item for item in read('companion-cached-reopen')['files']}
removed_files = {item['name']: item for item in read('companion-alice-files-removed')['files']}
deleted = sorted(set(before_files) - set(removed_files))
assert len(deleted) == 4
assert any(before_files[name]['sha256'] == 'd8211269aed55ded8302f289950936db8368b4d4d384c463b722034152f8f1d2' for name in deleted)
result = {'sourceCommit': '71af2886e722b7366d4d335622e55e18a151a3e0', 'snapshots': checks,
          'all69ActionsUnchangedImmediatelyAcrossCompanionInstall': True,
          'normalInstalledSha256': normal['installedApkSha256'], 'companionInstalledSha256': final['installedApkSha256'],
          'changedNonSignatureApkEntries': changed, 'ownedAccountRetained': len(owned), 'ownedAccountPending': 0,
          'actualPluginObjectsMatchingExactPayloadsAndCausalActions': len(server['objects']),
          'ownedActionsContainingNonAsciiValues': len(unicode_actions), 'explicitSyncNowPerformed': False,
          'originalAccountRecoveryProved': False, 'originalRetained': 44, 'originalPending': 28,
          'finalFilesDirectoryBytes': sum(item['bytes'] for item in final['files']),
          'beforeFirstOcrFilesDirectoryBytes': sum(item['bytes'] for item in before['files']),
          'firstOcrFilesDirectoryBytes': sum(item['bytes'] for item in first['files']),
          'finalOcrCacheBytes': sum(item['bytes'] for item in final['files'] if '.bookfin-ocr/' in item['name']),
          'modelBytes': model['bytes'], 'firstCacheBytes': first_cache['bytes'],
          'filesDirectoryLimit': 'Logical file lengths under the application files directory only. Excludes databases, cache directory, APK, compiled code and system StorageStats.',
          'companionRemovalFiles': deleted, 'companionRemovalBytes': sum(before_files[name]['bytes'] for name in deleted),
          'endState': {'signedIn': True, 'foreground': 'Unsaved Reading bookmark dialog', 'ownedDownloadsRemain': 5,
                       'network': final['network'], 'musicMuted': 'Muted: true' in final['audio'],
                       'uiCleanupCompleted': False, 'reason': 'Required stop after a failed field-entry retry.'}}
(OUTPUT / 'audit.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({key: result[key] for key in ['ownedAccountRetained', 'ownedAccountPending', 'actualPluginObjectsMatchingExactPayloadsAndCausalActions', 'originalRetained', 'originalPending', 'modelBytes', 'firstCacheBytes', 'finalOcrCacheBytes', 'companionRemovalBytes']}))
print(json.dumps([{key: entry[key] for key in ['label', 'referenceWords', 'wordEdits', 'characterEdits'] if key in entry} for entry in scores]))
