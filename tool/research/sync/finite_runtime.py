import datetime
import hashlib
import json
import os
import sys
import urllib.parse
import uuid

from experiments import EVIDENCE, context, record
from finite_journal import DEVICES, Journal, cleanup_plan, discover
from fixture import ROOT, private_json
from playlist_protocol import create, measure_privacy


STATE_FILE = ROOT / "finite-state.json"
PREFIX = "BookfinFinite-t3-16d73e22"


def encoded(document):
    return json.dumps(document, sort_keys=True, separators=(",", ":"))


def digest(document):
    return hashlib.sha256(encoded(document).encode()).hexdigest()


def operation(device, sequence, context, record_id="bookmark", kind="put", value="synthetic note"):
    return {"device": device, "sequence": sequence, "context": context,
            "record": record_id, "kind": kind, "value": value if kind == "put" else None}


def publish(client, namespace, kind, payload):
    document = {"namespace": namespace, "kind": kind, **payload}
    name = encoded(document)
    if len(name.encode()) > 65536:
        raise ValueError("Object exceeds this experiment's 64 KiB envelope; do not truncate")
    identifier = create(client, namespace + "-pending-" + uuid.uuid4().hex)
    client.json("POST", "/Playlists/" + identifier, {"Name": name, "IsPublic": False})
    assert client.json("GET", "/Items/" + identifier)["Name"] == name
    return identifier


def inventory(client, namespace, page_size=4):
    items, requests, response_bytes = [], 0, 0
    while True:
        if requests >= 128:
            raise RuntimeError("Research inventory exceeded 128 requests; do not use an incomplete scan")
        query = {"Recursive": "true", "IncludeItemTypes": "Playlist",
                 "SortBy": "SortName", "SortOrder": "Ascending", "StartIndex": len(items), "Limit": page_size}
        status, _, body = client.request("GET", "/Items?" + urllib.parse.urlencode(query))
        assert status == 200
        page = json.loads(body)
        requests += 1
        response_bytes += len(body)
        items.extend(page["Items"])
        if len(page["Items"]) < page_size:
            break
    assert len({item["Id"] for item in items}) == len(items)
    matching = []
    for item in items:
        try:
            document = json.loads(item["Name"])
        except (KeyError, TypeError, json.JSONDecodeError):
            document = None
        if ((isinstance(document, dict) and document.get("namespace") == namespace)
                or item.get("Name", "").startswith(namespace + "-pending-")):
            matching.append(item)
    return matching, {"pageSize": page_size, "requests": requests, "itemsVisited": len(items),
                   "matchingObjects": len(matching),
                   "httpResponseBytes": response_bytes,
                   "storedNameUtf8Bytes": sum(len(item["Name"].encode()) for item in matching)}


def stable_inventory(client, namespace, page_size=4):
    first, first_cost = inventory(client, namespace, page_size)
    second, second_cost = inventory(client, namespace, page_size)
    assert sorted((item["Id"], item["Name"]) for item in first) == sorted(
        (item["Id"], item["Name"]) for item in second), "Research schedule must be quiescent for cleanup"
    return second, {"scans": 2, "requests": first_cost["requests"] + second_cost["requests"],
                    "itemsVisited": first_cost["itemsVisited"] + second_cost["itemsVisited"],
                    "httpResponseBytes": first_cost["httpResponseBytes"] + second_cost["httpResponseBytes"],
                    "pageSize": page_size, "storedNameUtf8Bytes": second_cost["storedNameUtf8Bytes"]}


def file_bytes(namespace):
    matched = []
    for path in (ROOT / "data").rglob("*"):
        if path.is_file() and path.suffix in (".xml", ".m3u", ".m3u8", ".nfo"):
            if namespace in str(path.relative_to(ROOT)) or namespace.encode() in path.read_bytes():
                matched.append(path)
    return {"playlistFiles": len(matched), "playlistFileBytes": sum(path.stat().st_size for path in matched),
            "includesDatabaseIndexesLogsOrFilesystemAllocation": False}


def retain(namespace, journal):
    state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
    assert namespace not in state, "Do not overwrite an existing experiment"
    state[namespace] = journal.checkpoint()
    private_json(STATE_FILE, state)


def cleanup(client, namespace, journal, checkpoint_id):
    items, cost = stable_inventory(client, namespace)
    confirmed, batches, checkpoints = discover(items, namespace)
    assert confirmed.checkpoint() == journal.checkpoint()
    checkpoint_item = next(item for item in items if item["Id"] == checkpoint_id)
    replacement = Journal(json.loads(checkpoint_item["Name"])["state"])
    assert replacement.checkpoint() == confirmed.checkpoint()
    _, removable = cleanup_plan(replacement, batches, checkpoints)
    for identifier in removable:
        client.json("DELETE", "/Items/" + identifier)
        assert client.request("GET", "/Items/" + identifier)[0] == 404
    return {"removedObjects": len(removable), "discovery": cost}


def schedule():
    _, clients = context()
    alice, bob = clients["alice"], clients["bob"]
    namespace = PREFIX + "-schedule"
    assert not inventory(alice, namespace)[0]
    earlier = operation("device-a", 1, {"device-a": 0, "device-b": 0})
    later = operation("device-a", 2, {"device-a": 1, "device-b": 0}, value="device-a edit")
    concurrent = operation("device-b", 1, {"device-a": 1, "device-b": 0}, value="device-b edit")
    publish(alice, namespace, "batch", {"operations": [later]})
    missing, _, _ = discover(inventory(alice, namespace)[0], namespace)
    assert missing.coverage == dict.fromkeys(DEVICES, 0) and missing.pending_count == 1
    publish(alice, namespace, "checkpoint", {"state": missing.checkpoint()})
    publish(alice, namespace, "batch", {"operations": [earlier]})
    base = Journal()
    base.receive([earlier])
    first, second = Journal(base.checkpoint()), Journal(base.checkpoint())
    first.receive([later])
    second.receive([concurrent])
    publish(alice, namespace, "checkpoint", {"state": first.checkpoint()})
    publish(alice, namespace, "checkpoint", {"state": second.checkpoint()})
    joined, _, _ = discover(inventory(alice, namespace)[0], namespace)
    assert joined.values("bookmark") == ["device-a edit", "device-b edit"]
    assert joined.conflict_count == 1
    deletion = operation("device-b", 2, dict(joined.coverage), kind="delete")
    publish(alice, namespace, "batch", {"operations": [deletion]})
    joined.receive([deletion])
    checkpoint_id = publish(alice, namespace, "checkpoint", {"state": joined.checkpoint()})
    removed = cleanup(alice, namespace, joined, checkpoint_id)
    for _ in range(2):
        publish(alice, namespace, "batch", {"operations": [earlier]})
    retried, _, _ = discover(inventory(alice, namespace)[0], namespace)
    assert retried.values("bookmark") == [] and retried.deletion_count == 1
    delayed_removed = cleanup(alice, namespace, retried, checkpoint_id)
    fresh, _, _ = discover(inventory(alice, namespace)[0], namespace)
    assert fresh.checkpoint() == joined.checkpoint()
    payload = alice.json("GET", "/Items/" + checkpoint_id)["Name"]
    privacy = measure_privacy(alice, bob, checkpoint_id, payload)
    retain(namespace, fresh)
    record("finite-schedule", {"runtimeVersion": clients["admin"].json("GET", "/System/Info")["Version"],
        "fixedResearchIdentities": list(DEVICES), "identityExpiry": False,
        "missingEarlierActionCoverage": dict.fromkeys(DEVICES, 0), "missingEarlierActionBuffered": True,
        "independentCheckpointEditsPreserved": 2, "concurrentConflictPreserved": True,
        "deleteAfterObservingBothEdits": True, "coveredObjectsRemoved": removed["removedObjects"],
        "delayedRetryPhysicalObjects": 2, "delayedRetryObjectsRemoved": delayed_removed["removedObjects"],
        "freshDiscoveryLiveBookmarks": 0, "retainedDeletionWitnesses": fresh.deletion_count,
        "coverageAfterCleanup": fresh.coverage, "privacy": privacy,
        "networkConcurrency": "controlled sequential publication of independently computed checkpoints",
        "modelInterpretation": "Python journal reducer applied to actual server payloads; not Jellyfin merge logic"})


def workload():
    _, clients = context()
    alice = clients["alice"]
    namespace = PREFIX + "-workload"
    assert not inventory(alice, namespace)[0]
    all_actions, published = [], []
    for device in DEVICES:
        actions = []
        for revision in range(6):
            for number in range(100):
                sequence = len(actions) + 1
                actions.append(operation(device, sequence,
                    {identity: sequence - 1 if identity == device else 0 for identity in DEVICES},
                    f"{device}-bookmark-{number:03}", value=f"synthetic revision {revision} " + "x" * 64))
        for number in range(20):
            sequence = len(actions) + 1
            actions.append(operation(device, sequence,
                {identity: sequence - 1 if identity == device else 0 for identity in DEVICES},
                f"{device}-bookmark-{number:03}", kind="delete"))
        state = Journal()
        state.receive(actions)
        all_actions.extend(actions)
        for start in range(0, len(actions), 100):
            published.append(publish(alice, namespace, "batch", {"operations": actions[start:start + 100]}))
        published.append(publish(alice, namespace, "checkpoint", {"state": state.checkpoint()}))
    before, discovery_before = stable_inventory(alice, namespace)
    assert {item["Id"] for item in before} == set(published), "Inventory omitted an acknowledged object"
    joined, batches, checkpoints = discover(before, namespace)
    assert len(batches) == 14 and len(checkpoints) == 2
    assert joined.coverage == {device: 620 for device in DEVICES}
    assert joined.deletion_count == 40 and len(joined.records) == 200
    before_files = file_bytes(namespace)
    _, wide_cost = stable_inventory(alice, namespace, 128)
    checkpoint_id = publish(alice, namespace, "checkpoint", {"state": joined.checkpoint()})
    peak, _ = inventory(alice, namespace)
    removed = cleanup(alice, namespace, joined, checkpoint_id)
    after, discovery_after = stable_inventory(alice, namespace)
    restored, remaining_batches, remaining_checkpoints = discover(after, namespace)
    assert restored.checkpoint() == joined.checkpoint() and len(after) == 1
    retain(namespace, restored)
    record("finite-workload", {"runtimeVersion": clients["admin"].json("GET", "/System/Info")["Version"],
        "workload": {"devices": 2, "actions": len(all_actions), "bookmarksCreated": 200,
                     "revisionsPerBookmarkIncludingCreation": 6, "bookmarksDeleted": 40,
                     "retainedLiveBookmarks": 160, "retainedDeletionWitnesses": 40,
                     "valuePaddingCharacters": 64, "maximumActionsPerBatch": 100,
                     "userVisibleListeningHistoryIncluded": False},
        "beforeCleanup": {"batchPlaylists": len(batches), "checkpointPlaylists": len(checkpoints),
                          "totalPlaylists": len(before), **before_files},
        "publicationPeak": {"totalPlaylists": len(peak), "checkpointPlaylists": 3,
                            "storedNameUtf8Bytes": sum(len(item["Name"].encode()) for item in peak)},
        "cleanup": removed,
        "afterCleanup": {"batchPlaylists": len(remaining_batches), "checkpointPlaylists": len(remaining_checkpoints),
                         "totalPlaylists": len(after), **file_bytes(namespace)},
        "discoveryBeforePage4": discovery_before, "discoveryBeforePage128": wide_cost,
        "discoveryAfterPage4": discovery_after,
        "stableInventoryIsSnapshotGuaranteeUnderContinuousMutation": False,
        "acknowledgedPublicationIdsMatchedInventory": True,
        "checkpointStateSha256": digest(restored.checkpoint()), "productionPolicySelected": False})


def compatibility(phase, expected_version):
    _, clients = context()
    version = clients["admin"].json("GET", "/System/Info")["Version"]
    assert version == expected_version
    assert not list((ROOT / "data/plugins").rglob("Jellyfin.Plugin.JellyfinEnhanced.dll"))
    results = []
    for namespace, expected in json.loads(STATE_FILE.read_text()).items():
        items, cost = stable_inventory(clients["alice"], namespace)
        restored, batches, checkpoints = discover(items, namespace)
        assert restored.checkpoint() == expected and not batches and len(checkpoints) == 1
        item = items[0]
        privacy = measure_privacy(clients["alice"], clients["bob"], item["Id"], item["Name"])
        results.append({"namespace": namespace, "checkpointStateSha256": digest(expected),
                        "exactCheckpointPayloadSha256": hashlib.sha256(item["Name"].encode()).hexdigest(),
                        "coverage": restored.coverage, "liveVersions": sum(len(restored.values(key)) for key in restored.records),
                        "deletionWitnesses": restored.deletion_count, "privacy": privacy, "discovery": cost})
    baseline = ROOT / "finite-upgrade-baseline.json"
    fingerprints = [{key: result[key] for key in ["namespace", "checkpointStateSha256", "exactCheckpointPayloadSha256"]}
                    for result in results]
    if expected_version == "12.3.0":
        private_json(baseline, fingerprints)
    else:
        assert fingerprints == json.loads(baseline.read_text())
    record(phase, {"specifiedPair": ["12.3.0", "12.4.0"], "runtimeVersion": version,
                   "sameFixtureIdentityChecked": True, "namespaces": results,
                   "enhancedPluginInstalled": False, "rollbackToOldBinaryTested": False,
                   "generalUpgradeCompatibilityEstablished": False})


def model_costs():
    rows = []
    for count in [10, 100, 1000]:
        journal = Journal()
        for number in range(count):
            for kind in ["put", "delete"]:
                sequence = journal.coverage["device-a"] + 1
                journal.receive([operation("device-a", sequence, dict(journal.coverage),
                                           f"bookmark-{number:06}", kind=kind)])
        journal.check_invariants()
        rows.append({"distinctBookmarksCreatedThenDeleted": count, "liveBookmarks": 0,
                     "retainedDeletionWitnesses": journal.deletion_count,
                     "checkpointStateUtf8Bytes": len(encoded(journal.checkpoint()).encode()),
                     "fitsExperiment64KiBEnvelope": len(encoded(journal.checkpoint()).encode()) <= 65536})
    gap = Journal()
    gap.receive([operation("device-a", sequence, {"device-a": sequence - 1, "device-b": 0})
                 for sequence in range(2, 1002)])
    assert gap.pending_count == 1000 and gap.coverage["device-a"] == 0
    result = {"evidenceClass": "research-model-not-server", "observedAtUtc": datetime.datetime.now(datetime.UTC).isoformat(),
              "fixedResearchIdentities": list(DEVICES), "expiryPolicy": None, "deletionGrowth": rows,
              "missingFirstActionSchedule": {"withheld": "device-a:1", "delivered": "device-a:2..1001",
                                            "coverage": gap.coverage, "pendingActions": gap.pending_count,
                                            "checkpointStateUtf8Bytes": len(encoded(gap.checkpoint()).encode())},
              "fixedLifetimeStorageBoundProved": False,
              "blocker": "This candidate retains one deletion witness per deleted record and all actions above an unresolved gap"}
    (EVIDENCE / "finite-model-costs.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Wrote model-only finite-model-costs.json")


if __name__ == "__main__":
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise SystemExit("Run through nix develop ./tool/research/sync")
    commands = {"schedule": schedule, "workload": workload, "model-costs": model_costs,
                "before-upgrade": lambda: compatibility("finite-before-upgrade", "12.3.0"),
                "after-upgrade": lambda: compatibility("finite-after-upgrade", "12.4.0"),
                "after-new-restart": lambda: compatibility("finite-after-new-restart", "12.4.0")}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        raise SystemExit("Use schedule, workload, model-costs, before-upgrade, after-upgrade, or after-new-restart")
    commands[sys.argv[1]]()
