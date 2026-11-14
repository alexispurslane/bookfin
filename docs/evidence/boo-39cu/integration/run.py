import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path('/Users/alexispurslane/Development/bookfin')
out = pathlib.Path(__file__).parent
label, *command = sys.argv[1:]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
patch = subprocess.check_output(['git', 'diff', 'HEAD', '--', 'lib', 'test'], cwd=root)
(out / (label + '.patch.gz')).write_bytes(gzip.compress(patch, mtime=0))
sources = {
    str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
    for folder in ['lib', 'test']
    for path in sorted((root / folder).rglob('*.dart'))
}
source_bytes = json.dumps(sources, sort_keys=True).encode()
(out / (label + '.sources.json.gz')).write_bytes(gzip.compress(source_bytes, mtime=0))
log = out / (label + '.log')
with log.open('wb') as output:
    result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
raw = log.read_bytes()
(out / (label + '.log.gz')).write_bytes(gzip.compress(raw, mtime=0))
record = {
    'label': label, 'command': command, 'cwd': str(root), 'head': head,
    'started': started, 'ended': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'exitCode': result.returncode,
    'logSha256': hashlib.sha256(raw).hexdigest(),
    'patchSha256': hashlib.sha256(patch).hexdigest(),
    'sourceManifestSha256': hashlib.sha256(source_bytes).hexdigest(),
}
with (out / 'commands.jsonl').open('a') as ledger:
    ledger.write(json.dumps(record) + '\n')
events = []
for line in raw.decode(errors='replace').splitlines():
    try:
        event = json.loads(line)
        if isinstance(event, dict) and 'type' in event:
            events.append(event)
    except ValueError:
        pass
if events:
    tests = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
    done = [e for e in events if e['type'] == 'testDone' and not e.get('hidden')]
    summary = {
        'passed': sum(e['result'] == 'success' and not e['skipped'] for e in done),
        'skipped': [tests.get(e['testID'], {}) for e in done if e['skipped']],
        'errors': [e for e in events if e['type'] == 'error'],
        'completion': [e for e in events if e['type'] == 'done'],
    }
    (out / (label + '.results.json')).write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps({'passed': summary['passed'], 'skipped': len(summary['skipped']), 'errors': summary['errors'], 'completion': summary['completion']}))
else:
    print('\n'.join(raw.decode(errors='replace').splitlines()[-12:]))
print(json.dumps(record))
sys.exit(result.returncode)
