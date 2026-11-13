"""Archive exact commands and complete output for td-bz4y; run through Nix."""
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
name, *command = sys.argv[1:]


def archive(relative, data):
    path = EVIDENCE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    packed = gzip.compress(data, mtime=0)
    path.write_bytes(packed)
    return {"path": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(data).hexdigest(),
            "compressedSha256": hashlib.sha256(packed).hexdigest(), "bytes": len(data)}


started = datetime.datetime.now(datetime.timezone.utc).isoformat()
patch = subprocess.check_output(["git", "diff", "215273e35f986cd6682b47b1efc8eff627ddee34", "--",
                                "tool/research"], cwd=ROOT)
raw = EVIDENCE / f".{name}.log"
with raw.open("wb") as output:
    result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
data = raw.read_bytes()
record = {"name": name, "command": command, "cwd": str(ROOT), "started": started,
          "finished": datetime.datetime.now(datetime.timezone.utc).isoformat(), "exit": result.returncode,
          "sourcePatch": archive(f"patches/{name}.patch.gz", patch),
          "log": archive(f"logs/{name}.log.gz", data)}
with (EVIDENCE / "commands.jsonl").open("a") as output:
    output.write(json.dumps(record) + "\n")
raw.unlink()
with (EVIDENCE / "HASHES.sha256").open("w") as hashes:
    for path in sorted(EVIDENCE.rglob("*")):
        if path.is_file() and path.name != "HASHES.sha256" and not path.name.startswith("."):
            hashes.write(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(ROOT)}\n")
print(json.dumps(record))
print(data.decode(errors="replace")[-1800:])
sys.exit(result.returncode)
