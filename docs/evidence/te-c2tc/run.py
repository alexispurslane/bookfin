"""Record this ticket's commands, complete compressed output and source diffs."""
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
evidence = root / "docs/evidence/te-c2tc"
name, *command = sys.argv[1:]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
patch = subprocess.check_output(
    ["git", "diff", "5c8c92ecd348a7fb7c51ab176da6e616cfd2aa1c", "--", "*.dart"],
    cwd=root,
)


def archive(relative, data):
    path = evidence / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    packed = gzip.compress(data, mtime=0)
    path.write_bytes(packed)
    return {
        "path": str(path.relative_to(root)),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "compressedBytes": len(packed),
        "compressedSha256": hashlib.sha256(packed).hexdigest(),
    }


patch_record = archive(f"patches/{name}.patch.gz", patch)
raw = evidence / f".{name}.log"
with raw.open("wb") as output:
    result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
data = raw.read_bytes()
record = {
    "name": name,
    "command": command,
    "cwd": str(root),
    "started": started,
    "finished": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "exit": result.returncode,
    "sourcePatch": patch_record,
    "log": archive(f"logs/{name}.log.gz", data),
}
with (evidence / "commands.jsonl").open("a") as output:
    output.write(json.dumps(record) + "\n")
raw.unlink()
print(json.dumps(record))
print(data.decode(errors="replace")[-2200:])
sys.exit(result.returncode)
