from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sqlite3
import stat
import subprocess
import time
import unittest

from dedicated_fixture import CACHE
from test_outbox import PendingActions
from test_storage import DedicatedStorage


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


class Outcomes(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.outcomes = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.outcomes.append({"test": test.id(), "outcome": "passed"})

    def addFailure(self, test, error):
        super().addFailure(test, error)
        self.outcomes.append({"test": test.id(), "outcome": "failed"})

    def addError(self, test, error):
        super().addError(test, error)
        self.outcomes.append({"test": test.id(), "outcome": "error"})


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def listener_present(port):
    with socket.socket() as connection:
        connection.settimeout(1)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def collect(result, elapsed):
    server = DedicatedStorage.server
    databases = list(server.root.rglob("bookfin-storage-v1.sqlite"))
    if len(databases) != 1:
        raise AssertionError("Exactly one dedicated storage database must exist")
    database = databases[0]
    with closing(sqlite3.connect(database)) as connection:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        accounts = {}
        for name, account in server.accounts.items():
            owner = account["id"].replace("-", "")
            rows, deleted, payload_bytes, sequence = connection.execute("""
                SELECT count(*), coalesce(sum(payload IS NULL),0),
                    coalesce(sum(length(CAST(payload AS BLOB))),0), coalesce(max(sequence),0)
                FROM objects WHERE owner=?""", (owner,)).fetchone()
            accounts[name] = {"objects": rows, "deletionMarkers": deleted, "livePayloadUtf8Bytes": payload_bytes,
                              "lastSequence": sequence}
    source_files = list(HERE.glob("*.py")) + list(HERE.glob("*.cs")) + list(HERE.glob("*.csproj"))
    source_files += list(HERE.glob("*.props"))
    source_files += [HERE.parent / "sync" / name for name in
                     ("flake.nix", "flake.lock", "sources.json", "finite_journal.py", "fixture.py")]
    red_phases = {}
    for name in ("red-storage", "red-outbox", "red-acknowledgment", "red-null", "red-scope-race", "red-review-outbox", "red-review-null"):
        path = CACHE / (name + ".txt")
        if path.exists():
            red_phases[name] = [line for line in path.read_text().splitlines()
                                if re.match(r"^(FAIL:|ERROR:|AssertionError:|sqlite3.OperationalError:|Ran \d+ test|FAILED \()", line)]
    server_artifact = Path(os.environ["BOOKFIN_SYNC_SERVER"])
    evidence = {
        "ticket": "boo-dez0", "measuredAtUtc": datetime.now(timezone.utc).isoformat(),
        "baseCommit": "756ae5f", "purpose": "Disposable bounded feasibility proof; not production sync",
        "runtime": {"jellyfin": "12.4.0", "includedDotnet": "10.0.14", "sdk": subprocess.check_output(
            ["dotnet", "--version"], text=True).strip(), "host": "aarch64-darwin",
            "serverArchivePin": "tool/research/sync/sources.json",
            "serverDllSha256": sha256(server_artifact / "jellyfin.dll"),
            "pluginDllSha256": sha256(CACHE / "build/Bookfin.Storage.dll"),
            "sourceSha256": {str(path.relative_to(ROOT)): sha256(path) for path in sorted(source_files)}},
        "checks": {"testsRun": result.testsRun, "successful": result.wasSuccessful(),
                   "elapsedSeconds": round(elapsed, 3), "outcomes": result.outcomes,
                   "sqliteIntegrity": integrity, "invariantSwitchEnabled": True},
        "accounts": accounts, "databaseBytesAfterShutdown": database.stat().st_size,
        "starts": server.starts, "stops": server.stops, "redPhases": red_phases,
        "cleanup": {"ownProcessStopped": server.process.poll() is not None,
                    "port7464HasListener": listener_present(7464), "port7465HasListener": listener_present(7465),
                    "runtimeDirectoryMode": oct(stat.S_IMODE(server.root.stat().st_mode)),
                    "privateFileModes": {path.name: oct(stat.S_IMODE(path.stat().st_mode)) for path in
                                         (server.root / "accounts.json", server.root / "passwords.json", database)},
                    "state": "Retained under ignored .cache/plugin/run-*/; no production state accessed"},
        "limits": {"concurrentWorkers": 8, "independentWrites": 80, "payloadUtf8BytesPerObject": 65536,
                   "objectsPerPage": 4, "discoveryRequestBudget": 128,
                   "automaticExpiry": "No expiry implemented; finite tests do not prove infinite durability",
                   "lifetimeStorageBound": "Not established; retained operations and deletion markers grow",
                   "productionIntegration": False, "upgradeTested": False, "powerLossTested": False},
    }
    if integrity != "ok" or not evidence["cleanup"]["ownProcessStopped"]:
        raise AssertionError("Storage integrity or process cleanup failed")
    if evidence["cleanup"]["port7464HasListener"] or evidence["cleanup"]["port7465HasListener"]:
        raise AssertionError("The experiment ports still have a listener")
    return evidence


if __name__ == "__main__":
    started = time.monotonic()
    suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(test)
                               for test in (PendingActions, DedicatedStorage))
    result = unittest.TextTestRunner(verbosity=2, resultclass=Outcomes).run(suite)
    if result.wasSuccessful():
        evidence = collect(result, time.monotonic() - started)
        destination = HERE / "evidence/runtime.json"
        destination.parent.mkdir(exist_ok=True)
        destination.write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"Sanitized evidence: {destination.relative_to(ROOT)}")
    raise SystemExit(0 if result.wasSuccessful() else 1)
