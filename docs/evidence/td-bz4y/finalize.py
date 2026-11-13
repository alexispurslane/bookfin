"""Verify the archived record and keep the sole review's original verdicts."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
REVIEWED = "0ae29400c392a81e46d48eaeebaa93d63e676617"
original = json.loads((EVIDENCE / "review-original.json").read_text())
text = original["originalText"]
report = json.loads(re.search(r"```json\n([\s\S]*?)\n```", text)[1])
assert original["status"] == "completed"
assert report["head"] == REVIEWED
assert report["overallVerdict"] == "pass"
assert report["requiredChanges"] == []
sections = ("correctness", "ticketFulfillment", "design")
for section in sections:
    assert report[section]["verdict"] == "pass"
    assert report[section]["findings"] == []
(EVIDENCE / "review-original.txt.gz").write_bytes(gzip.compress(text.encode(), mtime=0))
assert gzip.decompress((EVIDENCE / "review-original.txt.gz").read_bytes()).decode() == text

code_changes = subprocess.check_output(
    ["git", "diff", REVIEWED, "--name-only", "--", "tool", "lib", "test", "nix", "flake.nix", "flake.lock"],
    cwd=ROOT, text=True,
).splitlines()
assert not code_changes, code_changes
resolutions = {
    "reviewedHead": REVIEWED,
    "originalReview": "docs/evidence/td-bz4y/review-original.json",
    "originalMessageSha256": hashlib.sha256(text.encode()).hexdigest(),
    "verbatimCompressedMessage": "docs/evidence/td-bz4y/review-original.txt.gz",
    "link": original["link"],
    "originalVerdicts": {section: report[section]["verdict"] for section in sections},
    "originalFindings": {section: report[section]["findings"] for section in sections},
    "originalGaps": {section: report[section]["gaps"] for section in sections},
    "unavailableChecks": report["unavailableChecks"],
    "resolutions": [],
    "implementationUnchangedSinceReview": True,
    "secondReview": False,
    "materialUnverifiedRequirements": [],
    "forks": [],
}
(EVIDENCE / "review-resolutions.json").write_text(json.dumps(resolutions, indent=2) + "\n")

# Check the immutable command logs and source patches rather than the changing
# manifest itself. run.py refreshes the final manifest after this command ends.
records = [json.loads(line) for line in (EVIDENCE / "commands.jsonl").read_text().splitlines()]
for record in records:
    for key in ("log", "sourcePatch"):
        artifact = record[key]
        packed = (ROOT / artifact["path"]).read_bytes()
        assert hashlib.sha256(packed).hexdigest() == artifact["compressedSha256"]
        assert hashlib.sha256(gzip.decompress(packed)).hexdigest() == artifact["sha256"]
print(json.dumps({"archivedCommandsVerified": len(records), "originalVerdicts": resolutions["originalVerdicts"],
                  "originalMessageSha256": resolutions["originalMessageSha256"],
                  "implementationUnchangedSinceReview": True, "reviewerFinished": True}))
