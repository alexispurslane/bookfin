#!/usr/bin/env python3
"""Archive this ticket's sequential checks, including failed attempts."""
import datetime, gzip, hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[3]
archive = pathlib.Path(__file__).resolve().parent
label, *command = sys.argv[1:]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
diff = subprocess.check_output(['git', 'diff', '2f5f0393d4d5961627b7eb84f7c2f7725ab762aa'], cwd=root)
sources = {}
for folder in ['lib', 'test']:
    for path in sorted((root / folder).rglob('*.dart')):
        sources[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
source_bytes = json.dumps(sources, sort_keys=True).encode()
(archive / (label + '.sources.json.gz')).write_bytes(gzip.compress(source_bytes, mtime=0))
log = archive / (label + '.log')
with log.open('wb') as out:
    result = subprocess.run(command, cwd=root, stdout=out, stderr=subprocess.STDOUT)
data = log.read_bytes()
packed = gzip.compress(data, mtime=0)
(archive / (label + '.log.gz')).write_bytes(packed)
record = dict(label=label, command=command, cwd=str(root), started=started,
              ended=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              head=head, diff_sha256=hashlib.sha256(diff).hexdigest(),
              source_manifest_sha256=hashlib.sha256(source_bytes).hexdigest(),
              exit=result.returncode, log_sha256=hashlib.sha256(data).hexdigest(),
              archive_sha256=hashlib.sha256(packed).hexdigest())
with (archive / 'commands.jsonl').open('a') as out:
    out.write(json.dumps(record) + '\n')
log.unlink()
print(json.dumps(record))
print('\n'.join(data.decode(errors='replace').replace('\r', '\n').splitlines()[-18:]))
sys.exit(result.returncode)
