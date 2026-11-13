"""Ticket-local command recorder; run from the worktree root, not app code."""

import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys


root = Path(__file__).resolve().parent
name, *command = sys.argv[1:]
log = root / "logs" / f"{name}.log"
if log.exists():
    raise SystemExit(f"Refusing to overwrite {log}")
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
diff = subprocess.check_output(["git", "diff", "HEAD", "--", "lib", "test"])
patch = root / "diagnostics" / f"{name}.patch"
patch.write_bytes(diff)
with log.open("wb") as output:
    result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT)
record = {
    "name": name,
    "command": command,
    "cwd": str(Path.cwd()),
    "head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "startedUtc": started,
    "finishedUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "exitCode": result.returncode,
    "log": str(log.relative_to(root)),
    "logSha256": hashlib.sha256(log.read_bytes()).hexdigest(),
    "sourcePatch": str(patch.relative_to(root)),
    "sourcePatchSha256": hashlib.sha256(diff).hexdigest(),
}
with (root / "commands.jsonl").open("a") as output:
    output.write(json.dumps(record) + "\n")
print(json.dumps(record, indent=2))
print(log.read_text(errors="replace")[-1800:])
sys.exit(result.returncode)
