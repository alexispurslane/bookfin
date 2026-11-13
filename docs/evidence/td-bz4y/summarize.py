"""Summarize archived evidence without replacing the complete command logs."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = Path(__file__).resolve().parent
BASE = "215273e35f986cd6682b47b1efc8eff627ddee34"


def write(name, value):
    (EVIDENCE / name).write_text(json.dumps(value, indent=2) + "\n")


commands = [json.loads(line) for line in (EVIDENCE / "commands.jsonl").read_text().splitlines()]
results = []
for command in commands:
    log = gzip.decompress((ROOT / command["log"]["path"]).read_bytes()).decode()
    assert hashlib.sha256(log.encode()).hexdigest() == command["log"]["sha256"]
    row = {"name": command["name"], "exit": command["exit"],
           "resultLines": re.findall(r"^.*(?:Ran \d+ tests|OK(?: \(skipped=\d+\))?$|FAILED \(|All tests passed|Some tests failed|warning -|No issues found|Formatted \d+).*$", log, re.MULTILINE),
           "skipLines": [line for line in log.splitlines() if "... skipped" in line or "Skip:" in line]}
    results.append(row)
    if command["name"] in ("09-dart-red", "10-dart-green"):
        observations = [json.loads(line.split("OBSERVATION ", 1)[1])
                        for line in log.splitlines() if "OBSERVATION " in line]
        write(command["name"] + "-observations.json", observations)
write("results.json", results)

preservation = []
for before, after, language in [("python-controlled-red.json", "python-controlled-green.json", "Python"),
                                 ("09-dart-red-observations.json", "10-dart-green-observations.json", "Dart")]:
    red = json.loads((EVIDENCE / before).read_text())
    green = json.loads((EVIDENCE / after).read_text())
    assert len(red) == len(green)
    for index, (old, new) in enumerate(zip(red, green)):
        old_entries = [{key: value for key, value in entry.items() if key != "time"} for entry in old["entries"]]
        new_entries = [{key: value for key, value in entry.items() if key != "time"} for entry in new["entries"]]
        assert old_entries == new_entries, (language, index)
        if language == "Dart":
            assert [entry for entry in old["entries"] if entry["name"] != "OEBPS/content.opf"] == [
                entry for entry in new["entries"] if entry["name"] != "OEBPS/content.opf"]
    preservation.append({"language": language, "observationsCompared": len(red),
                         "entryOrderPayloadsCompressionAndAttributesPreserved": True,
                         "decodedOriginalEntryTimesPreserved": True if language == "Dart" else None})
write("preservation-observations.json", preservation)

changed = subprocess.check_output(["git", "diff", BASE, "--name-only"], cwd=ROOT, text=True).splitlines()
allowed = {"tool/research/epub_engines/test_prepare.py", "tool/research/epub_engines/test_calibrate.py",
           "tool/research/readers/dart_compat/test/compat_test.dart", "tool/research/sync/fixture.py"}
assert set(path for path in changed if not path.startswith(("docs/evidence/td-bz4y/", ".tickets/"))) <= allowed
unchanged = ["lib", "test", "tool/showcase_media.dart", "flake.nix", "flake.lock",
             "tool/research/readers/fixtures", "tool/research/readers/dart_compat/pubspec.yaml",
             "tool/research/readers/dart_compat/pubspec.lock", "tool/research/readers/dart_compat/test/corpus_test.dart",
             "tool/research/readers/navigator", "tool/research/epub_engines/prepare.py", "tool/research/epub_engines/calibrate.py"]
for path in unchanged:
    subprocess.run(["git", "diff", "--exit-code", BASE, "--", path], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
write("preserved.json", {"base": BASE, "unchangedPaths": unchanged, "changedTrackedPaths": changed})
print(json.dumps({"checks": len(results), "preservation": preservation,
                  "suiteResults": [row for row in results if any(key in row["name"] for key in ("full", "focused", "analysis"))]}, indent=2))
