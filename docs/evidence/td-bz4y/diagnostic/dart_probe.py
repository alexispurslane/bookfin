"""Temporarily route the real inline cover fixture through diagnostic access.

Use a private archive copy, then restore source and package config byte-for-byte.
No dependency cache edits, source-asset rewrites, public clock or lasting helper.
"""
import difflib
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "tool/research/readers/dart_compat"
stage = sys.argv[1]
config = PACKAGE / ".dart_tool/package_config.json"
source = PACKAGE / "test/compat_test.dart"
test = PACKAGE / "test/td_bz4y_times_test.dart"
before_config = config.read_bytes()
before_source = source.read_bytes()
packages = json.loads(before_config)
entry = next(entry for entry in packages["packages"] if entry["name"] == "archive")
original_package = Path(unquote(urlparse(entry["rootUri"]).path))
private_package = PACKAGE / f".dart_tool/td-bz4y-archive-{stage}"
shutil.copytree(original_package, private_package)
relative = "lib/src/archive/archive_file.dart"
original_dependency = (original_package / relative).read_bytes()
controlled_dependency = original_dependency.replace(b"import 'dart:convert';", b"import 'dart:convert';\r\nimport 'dart:async';")
old = b"late int lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;"
new = b"late int lastModTime = ((Zone.current[#tdBz4yArchiveTime] as DateTime?) ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;"
assert controlled_dependency.count(old) == 1
controlled_dependency = controlled_dependency.replace(old, new)
(private_package / relative).write_bytes(controlled_dependency)
entry["rootUri"] = private_package.as_uri()
text = before_source.decode()
start = text.index("    final archive = ZipDecoder().decodeBytes(")
end = text.index("    final book = await EpubReader.openBook(ZipEncoder().encode(archive));", start)
block = text[start:end]
instrumented = text[:start] + "    final bytes = diagnosticCoverArchive();\n" + text[end:].replace(
    "EpubReader.openBook(ZipEncoder().encode(archive))", "EpubReader.openBook(bytes)", 1)
instrumented += "\nList<int> diagnosticCoverArchive() {\n" + block + "    return ZipEncoder().encode(archive);\n}\n"
for name, data in [(f"{stage}-source-before.dart.gz", before_source),
                   (f"{stage}-source-instrumented.dart.gz", instrumented.encode()),
                   (f"{stage}-package-config-before.json.gz", before_config),
                   ("dependency-before.dart.gz", original_dependency),
                   ("dependency.patch.gz", "".join(difflib.unified_diff(
                       original_dependency.decode().splitlines(True), controlled_dependency.decode().splitlines(True),
                       fromfile="archive-4.6.0/" + relative, tofile="private-copy/" + relative)).encode())]:
    (EVIDENCE / "diagnostic" / name).write_bytes(gzip.compress(data, mtime=0))
input_path = PACKAGE.parent / "_out/mobi6-plain.epub"
input_before = input_path.read_bytes()
try:
    config.write_text(json.dumps(packages, indent=2) + "\n")
    source.write_text(instrumented)
    shutil.copyfile(EVIDENCE / "diagnostic/dart_times.dart", test)
    # Native initialization is not used by these three archive-only tests.
    # Invoke the pinned test runner directly: `dart test` refreshes package
    # resolution and replaces our private archive root before running tests.
    runner_entry = next(entry for entry in packages["packages"] if entry["name"] == "test")
    runner = Path(unquote(urlparse(runner_entry["rootUri"]).path)) / "bin/test.dart"
    command = ["dart", f"--packages={config}", str(runner), "--concurrency=2",
               "--reporter=expanded", "test/td_bz4y_times_test.dart"]
    print(json.dumps({"cwd": str(PACKAGE), "command": command}), flush=True)
    result = subprocess.run(command, cwd=PACKAGE)
finally:
    config.write_bytes(before_config)
    source.write_bytes(before_source)
    test.unlink(missing_ok=True)
    restoration = {"packageConfigRestored": config.read_bytes() == before_config,
                   "fixtureSourceRestored": source.read_bytes() == before_source,
                   "sourceInputRestored": input_path.read_bytes() == input_before,
                   "dependencyUntouched": (original_package / relative).read_bytes() == original_dependency,
                   "originalDependencySha256": hashlib.sha256(original_dependency).hexdigest(),
                   "sourceInputSha256": hashlib.sha256(input_before).hexdigest(),
                   "temporaryTestRemoved": not test.exists()}
    (EVIDENCE / f"dart-{stage}-restoration.json").write_text(json.dumps(restoration, indent=2) + "\n")
    assert all(value for value in restoration.values())
sys.exit(result.returncode)
