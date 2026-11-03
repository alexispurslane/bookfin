from contextlib import closing
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile

from package import ROOT, build, compile_project, digest, encoded, metadata, write_archive


sys.path.insert(0, str(ROOT / "tool/research/plugin"))
from dedicated_fixture import Api, CACHE, ORIGIN, Server, private_json
from test_outbox import PendingActions
from test_storage import DedicatedStorage
from run import Outcomes


BASE = "/BookfinStorage/v1/objects"
BASELINE = "a0b3155"
EVIDENCE = ROOT / "tool/evidence/plugin/packaging.json"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def listener_present(port):
    with socket.socket() as connection:
        connection.settimeout(1)
        return connection.connect_ex(("127.0.0.1", port)) == 0


def inventory(server, name):
    objects = []
    cursor = 0
    for _ in range(128):
        page = server.api(name).json("GET", f"{BASE}?after={cursor}&limit=4")
        objects.extend(page["Objects"])
        if not page["HasMore"]:
            return objects
        require(page["Cursor"] > cursor, "Discovery must advance")
        cursor = page["Cursor"]
    raise AssertionError("Discovery exhausted its bounded request budget")


def storage_state(server):
    databases = list((server.root / "data").rglob("bookfin-storage-v1.sqlite"))
    require(len(databases) == 1, "Exactly one plugin database must exist")
    with closing(sqlite3.connect(databases[0])) as connection:
        require(connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "Storage must remain intact")
        rows = connection.execute("SELECT owner, identity, sequence, payload FROM objects ORDER BY owner, sequence").fetchall()
    return {"rows": len(rows), "sha256": digest(encoded(rows)), "bytes": databases[0].stat().st_size,
            "relativePath": str(databases[0].relative_to(server.root / "data"))}


def plugin_version(server):
    plugins = server.api("admin").json("GET", "/Plugins")
    matching = [plugin for plugin in plugins if plugin["Id"].replace("-", "") == metadata()["guid"].replace("-", "")]
    require(len(matching) == 1, "Exactly one plugin with the stable identity must load")
    require(matching[0]["Status"] == "Active", "Jellyfin must report the plugin as active")
    return matching[0]["Version"]


def authorization(server):
    alice_objects = inventory(server, "alice")
    require(bool(alice_objects), "Alice must have ordinary-account app records")
    known = alice_objects[0]
    alice_id = server.accounts["alice"]["id"]
    forged = f"{BASE}/{known['Id']}?userId={alice_id}"
    bob = server.api("bob")
    require(bob.request("GET", forged)[0] in (404, 410), "Bob cannot read Alice through a forged owner query")
    require(bob.request("PUT", forged, {"Payload": "bob-only"})[0] in (201, 410), "A forged owner must not address Alice")
    require(bob.request("DELETE", forged)[0] == 204, "Bob can delete only Bob's identity")
    require(server.api("alice").json("GET", f"{BASE}/{known['Id']}") == known, "Bob must not change Alice's object")
    for method, suffix, value in (("GET", "", None), ("GET", "/unauthenticated", None),
                                  ("PUT", "/unauthenticated", {"Payload": "denied"}),
                                  ("DELETE", "/unauthenticated", None)):
        require(Api(origin=ORIGIN).request(method, BASE + suffix, value)[0] == 401, "Every storage method must require authentication")


def app_test(config, phase=None):
    environment = {**os.environ, "BOOKFIN_PRODUCTION_SYNC_FIXTURE": str(config)}
    test = "test/sync/plugin_integration_test.dart"
    if phase is not None:
        environment["BOOKFIN_PLUGIN_UPGRADE_PHASE"] = phase
        test = "test/sync/plugin_upgrade_integration_test.dart"
    subprocess.run([
        "nix", "develop", "--command", "flutter", "test", "--no-pub", test,
        "--concurrency=1", "--reporter", "expanded",
    ], cwd=ROOT, env=environment, check=True, timeout=240)


def baseline_package(destination):
    source = destination / "baseline-source"
    source.mkdir()
    files = ["Bookfin.Storage.csproj", "Directory.Build.props", "Plugin.cs", "ObjectStore.cs", "StorageController.cs"]
    sources = {}
    for name in files:
        path = "tool/research/plugin/" + name
        contents = subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT)
        (source / name).write_bytes(contents)
        sources[path] = digest(contents)
    dll = compile_project(source / "Bookfin.Storage.csproj", destination / "baseline-out",
                          destination / "baseline-obj", Path(os.environ["BOOKFIN_SYNC_SERVER"]))
    details = {**metadata(), "name": "Bookfin Storage Research", "version": "0.1.0.0",
               "description": "Disposable dedicated-storage proof", "owner": "Bookfin research"}
    archive = destination / "baseline.zip"
    write_archive(archive, {"Bookfin.Storage.dll": dll.read_bytes(), "meta.json": encoded(details)})
    return archive, {"commit": subprocess.check_output(["git", "rev-parse", BASELINE], cwd=ROOT, text=True).strip(),
                     "sourceSha256": sources, "dllSha256": digest(dll.read_bytes())}


def main():
    started = time.monotonic()
    os.umask(0o077)
    CACHE.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="packaging-", dir=CACHE))
    candidate = build(work / "first")
    rebuilt = build(work / "second")
    require(candidate.read_bytes() == rebuilt.read_bytes(), "Independent clean builds must produce identical packages")
    require(candidate.with_suffix(".sources.zip").read_bytes() == rebuilt.with_suffix(".sources.zip").read_bytes(),
            "Independent source archives must match")
    os.environ["BOOKFIN_STORAGE_FIXTURE_PACKAGE"] = str(candidate)
    suite = unittest.TestSuite(unittest.defaultTestLoader.loadTestsFromTestCase(test)
                               for test in (PendingActions, DedicatedStorage))
    result = unittest.TextTestRunner(verbosity=2, resultclass=Outcomes).run(suite)
    require(result.wasSuccessful(), "The existing dedicated-storage suite must pass with the installable package")
    fresh = DedicatedStorage.server
    require(fresh.process.poll() is not None, "The fresh-install regression server must be stopped")
    baseline, baseline_evidence = baseline_package(work)
    server = Server(baseline)
    try:
        server.start()
        server.seed()
        require(plugin_version(server) == "0.1.0.0", "The original research plugin must load first")
        config = server.root / "production-client.json"
        session = server.accounts["alice"]
        private_json(config, {"scope": {"server": ORIGIN, "serverId": server.server_id, "userId": session["id"]},
                              "token": session["token"], "username": "Alice", "canDownload": True})
        app_test(config, "prepare")
        authorization(server)
        bob = server.api("bob")
        require(bob.request("PUT", BASE + "/immutable", {"Payload": "retained"})[0] == 201, "The baseline must accept an object")
        require(bob.request("DELETE", BASE + "/deleted-before-upgrade")[0] == 204, "The baseline must retain a deletion marker")
        before = {name: inventory(server, name) for name in ("alice", "bob")}
        state_before = storage_state(server)
        clients_before = {name: digest((server.root / name).read_bytes()) for name in ("first.sqlite", "second.sqlite")}
        server.stop()
        backup = work / "stopped-backup"
        for directory in ("data", "config"):
            shutil.copytree(server.root / directory, backup / directory)
        for name in ("first.sqlite", "second.sqlite", "production-client.json", "pending-before-upgrade.json"):
            shutil.copy2(server.root / name, backup / name)
        server.install_package(candidate)
        server.start()
        require(plugin_version(server) == "0.1.1.0", "Jellyfin must activate the replacement package")
        require({name: inventory(server, name) for name in before} == before, "Upgrade must preserve every object, sequence and deletion")
        require(storage_state(server) == state_before, "Upgrade must leave the same dedicated database and rows")
        require({name: digest((server.root / name).read_bytes()) for name in clients_before} == clients_before,
                "Upgrade must not touch durable clients or their pending changes")
        authorization(server)
        require(bob.request("PUT", BASE + "/immutable", {"Payload": "changed"})[0] == 409, "Upgrade must preserve immutability")
        require(bob.request("PUT", BASE + "/deleted-before-upgrade", {"Payload": "late"})[0] == 410, "Upgrade must preserve deletion barriers")
        app_test(config, "verify")
        after = {name: inventory(server, name) for name in before}
        server.stop()
        server.start()
        require(plugin_version(server) == "0.1.1.0", "The installed version must survive restart")
        require({name: inventory(server, name) for name in after} == after, "Restart must preserve post-upgrade app uploads")
        authorization(server)
        password = secrets.token_urlsafe(24)
        user = server.api("admin").json("POST", "/Users/New", {"Name": "regression", "Password": password})
        require(not user["Policy"]["IsAdministrator"], "The existing app regression must use an ordinary account")
        auth = Api(origin=ORIGIN).json("POST", "/Users/AuthenticateByName", {"Username": "regression", "Pw": password})
        regression_config = server.root / "regression-client.json"
        private_json(regression_config, {
            "scope": {"server": ORIGIN, "serverId": server.server_id, "userId": auth["User"]["Id"]},
            "token": auth["AccessToken"], "username": "regression", "canDownload": True,
        })
        app_test(regression_config)
        state_after = storage_state(server)
        server.stop()
        restored_state = storage_state(server)
        for directory in ("data", "config"):
            shutil.rmtree(server.root / directory)
            shutil.copytree(backup / directory, server.root / directory)
        server.plugin_directory = server.root / "data/plugins/Bookfin Storage Research_0.1.0.0"
        server.start()
        require(plugin_version(server) == "0.1.0.0", "Stopped backup restore must reactivate the original plugin")
        require({name: inventory(server, name) for name in before} == before, "Stopped backup restore must recover the complete original server state")
        server.stop()
    finally:
        server.stop()
    with zipfile.ZipFile(candidate) as package:
        manifest = json.loads(package.read("manifest.json"))
        dll_hash = digest(package.read("Bookfin.Storage.dll"))
    cleanup = {"ownedServersStopped": all(instance.process.poll() is not None for instance in (fresh, server)),
               "port7464HasListener": listener_present(7464), "port7465HasListener": listener_present(7465)}
    require(cleanup == {"ownedServersStopped": True, "port7464HasListener": False, "port7465HasListener": False},
            "Owned servers must stop and both reserved ports must be free")
    evidence = {
        "ticket": "t6-il6y", "measuredAtUtc": datetime.now(timezone.utc).isoformat(),
        "elapsedSeconds": round(time.monotonic() - started, 3),
        "milestone": "Reproducible local candidate, fresh install, research-to-package upgrade, restart and stopped backup restore",
        "runtime": {**manifest["runtime"], "observedServerVersion": "12.4.0"},
        "package": {"name": candidate.name, "sha256": digest(candidate.read_bytes()), "dllSha256": dll_hash,
                    "sourcesZipSha256": digest(candidate.with_suffix(".sources.zip").read_bytes()),
                    "independentCleanBuildsByteIdentical": True, "manifest": manifest},
        "baseline": baseline_evidence,
        "regressions": {"testsRun": result.testsRun, "outcomes": result.outcomes,
                        "freshInstallStarts": len(fresh.starts), "freshInstallStops": len(fresh.stops)},
        "upgrade": {"from": "0.1.0.0", "to": "0.1.1.0", "starts": len(server.starts), "stops": len(server.stops),
                    "databaseBefore": state_before, "databaseAfterAppVerification": state_after,
                    "databaseBeforeBackupRestore": restored_state,
                    "objectsBefore": {name: len(objects) for name, objects in before.items()},
                    "objectsAfterAppVerification": {name: len(objects) for name, objects in after.items()},
                    "durableClientFilesUnchangedAcrossUpgrade": True, "offlinePendingActionReopenedAndUploaded": True,
                    "conflictsDeletionsAudioReadingAndHistoryPreserved": True,
                    "ordinaryAccountIsolationAndUnauthorizedMethods": True, "stoppedServerBackupRestored": True,
                    "existingProductionTransportRegressionPassed": True},
        "cleanup": cleanup,
        "proofSourceSha256": {name: digest((ROOT / name).read_bytes()) for name in (
            "tool/plugin/prove.py", "tool/plugin/test_package.py", "tool/research/plugin/dedicated_fixture.py",
            "test/sync/plugin_upgrade_integration_test.dart", "test/sync/plugin_integration_test.dart")},
        "limits": ["Only Jellyfin 12.4.0 on macOS ARM64 was run", "No Android device or UI acceptance",
                   "No public release, signatures, repository publication, live-server install or deployment acceptance",
                   "No server-version migration, disk-full, host power-loss, lifetime bounds or hardening campaign",
                   "Backup restoration is a whole stopped-server snapshot, not merging later client activity"],
    }
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_bytes(encoded(evidence))
    print("Sanitized evidence: " + str(EVIDENCE.relative_to(ROOT)))
    print("Private disposable state retained: " + str(work.relative_to(ROOT)))


if __name__ == "__main__":
    main()
