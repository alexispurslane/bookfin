"""Run one verification command and retain its output and source snapshot."""
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
evidence = Path(__file__).resolve().parent
name, *command = sys.argv[1:]
patch = subprocess.check_output(["git", "diff", "HEAD"], cwd=root)
untracked = subprocess.check_output(
    ["git", "ls-files", "--others", "--exclude-standard"], cwd=root, text=True
).splitlines()
for path in untracked:
    if path.endswith(".dart"):
        patch += subprocess.run(
            ["git", "diff", "--no-index", "/dev/null", path],
            cwd=root, stdout=subprocess.PIPE,
        ).stdout
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
result = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
output = result.stdout
for suffix, value in [("log", output), ("patch", patch)]:
    (evidence / f"{name}.{suffix}.gz").write_bytes(gzip.compress(value, mtime=0))
row = dict(name=name, command=command, head=head, started=started,
           ended=datetime.datetime.now(datetime.timezone.utc).isoformat(),
           exitCode=result.returncode,
           log=f"{name}.log.gz", logSha256=hashlib.sha256(output).hexdigest(),
           patch=f"{name}.patch.gz", patchSha256=hashlib.sha256(patch).hexdigest())
with (evidence / "commands.jsonl").open("a") as stream:
    stream.write(json.dumps(row) + "\n")
print(json.dumps(row))
print(output.decode(errors="replace")[-3500:])
sys.exit(result.returncode)
