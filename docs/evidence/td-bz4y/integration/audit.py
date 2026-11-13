import gzip
import hashlib
import json
from pathlib import Path
import subprocess

root = Path.cwd()
evidence = root / 'docs/evidence/td-bz4y'
base = '8effc9496e5a5d9d45929fbc54de8f746698c1cf'
child = 'b9ce8260324102db3d3d6c50ede32f8c74597c13'
sources = [
    'tool/research/epub_engines/test_prepare.py',
    'tool/research/epub_engines/test_calibrate.py',
    'tool/research/sync/fixture.py',
    'tool/research/readers/dart_compat/test/compat_test.dart',
]
verified = 0
for line in (evidence / 'HASHES.sha256').read_text().splitlines():
    expected, path = line.split('  ', 1)
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == expected, path
    verified += 1
records = [json.loads(line) for line in (evidence / 'commands.jsonl').read_text().splitlines()]
for record in records:
    for kind in ('log', 'sourcePatch'):
        item = record[kind]
        data = (root / item['path']).read_bytes()
        raw = gzip.decompress(data)
        assert hashlib.sha256(data).hexdigest() == item['compressedSha256']
        assert hashlib.sha256(raw).hexdigest() == item['sha256']
        assert len(raw) == item['bytes']
review = json.loads((evidence / 'review-original.json').read_text())
assert gzip.decompress((evidence / 'review-original.txt.gz').read_bytes()).decode() == review['originalText']
subprocess.run(['git', 'diff', '--exit-code', child, '--', *sources], check=True)
subprocess.run(['git', 'diff', '--exit-code', base, '--', 'lib', 'test', 'integration_test', 'tool/showcase_media.dart', 'tool/showcase_fixture.dart', 'flake.nix', 'flake.lock'], check=True)
subprocess.run(['git', 'diff', '--check', base], check=True)
subprocess.run(['git', 'diff', '--cached', '--check'], check=True)
sources.append('tool/research/readers/dart_compat/test/corpus_test.dart')
print(json.dumps({
    'parentBase': base,
    'childHead': child,
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'childEvidenceFilesVerified': verified,
    'childCommandRecordsVerified': len(records),
    'originalReviewPreserved': True,
    'fourReviewedSourcesUnchanged': True,
    'rootApplicationTestsAndEnvironmentUnchanged': True,
    'whitespaceClean': True,
    'sourceHashes': {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in sources},
}, indent=2))
