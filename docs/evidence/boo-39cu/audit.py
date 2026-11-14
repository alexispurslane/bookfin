"""Verify retained bytes and summarize every verification run, including skips."""
import collections
import gzip
import hashlib
import json
from pathlib import Path
import re

directory = Path(__file__).resolve().parent
root = directory.parents[2]
commands = [json.loads(line) for line in (directory / "commands.jsonl").read_text().splitlines()]
runs = []
for command in commands:
    for kind in ("log", "patch"):
        payload = gzip.decompress((directory / command[kind]).read_bytes())
        assert hashlib.sha256(payload).hexdigest() == command[f"{kind}Sha256"], command["name"]
    output = gzip.decompress((directory / command["log"]).read_bytes()).decode(errors="replace")
    events = []
    for line in output.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and "type" in value:
            events.append(value)
    row = dict(command)
    if events:
        completed = [event for event in events if event["type"] == "done"]
        row["frameworkCompleted"] = bool(completed)
        row["frameworkSuccess"] = completed[-1].get("success") if completed else None
        tests = {event["test"]["id"]: event["test"] for event in events if event["type"] == "testStart"}
        results = [event for event in events if event["type"] == "testDone" and not event.get("hidden")]
        row["counts"] = dict(collections.Counter(
            "skipped" if event.get("skipped") else event["result"] for event in results
        ))
        row["failures"] = [
            dict(test=tests.get(event["testID"]), result=event,
                 errors=[error for error in events if error["type"] == "error" and error.get("testID") == event["testID"]])
            for event in results if event["result"] != "success"
        ]
        row["skips"] = [tests[event["testID"]] for event in results if event.get("skipped")]
        (directory / f'{command["name"]}-results.json').write_text(json.dumps(row, indent=2) + "\n")
    else:
        row["failureNames"] = [line for line in output.splitlines() if "[E]" in line]
        row["testSummary"] = re.findall(r"^.*(?:All tests passed!|Some tests failed\.).*$", output, re.M)
    runs.append(row)

source_paths = [
    "lib/downloads/downloads.dart", "lib/downloads/local_downloads.dart",
    "lib/downloads/screen.dart", "lib/playback/playback.dart",
    "test/playback/download_removal_test.dart", "test/playback/replacement_test.dart",
    "test/downloads/tab_test.dart", "test/reader/book_words_reader_test.dart",
    "test/reader/admitted_books_test.dart", "test/reader/kept_pages_test.dart",
    "test/catalog/book_page_test.dart", "test/downloads/screen_test.dart",
]
summary = dict(
    auditCommand=["python3", "docs/evidence/boo-39cu/audit.py"],
    archivedHashesVerified=True,
    runs=runs,
    sourceSha256={path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in source_paths},
    exclusions=[
        "The full-suite skip entries name every omitted optional/external test and its framework metadata.",
        "No device, browser, live credentials/server actions, coverage or mutation campaign.",
        "Native framework acceptance remains parent-owned under t1-dth0.",
    ],
    diagnostics=[
        "Flutter test setup reports unavailable iphoneos and iphonesimulator SDKs. Host tests still execute; no iOS acceptance is claimed.",
        "JavaScript builds report WebAssembly dry-run incompatibilities in flutter_secure_storage_web and missing Cupertino font-family warnings. Both requested JavaScript builds succeed.",
    ],
)
(directory / "verification.json").write_text(json.dumps(summary, indent=2) + "\n")
hashes = {
    str(path.relative_to(directory)): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(directory.rglob("*"))
    if path.is_file() and path.name != "artifact-hashes.json"
}
(directory / "artifact-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
print(json.dumps({"hashesVerified": len(commands), "fullSuites": [
    {"name": row["name"], "exitCode": row["exitCode"], "counts": row["counts"]}
    for row in runs if "counts" in row
]}))
