import hashlib
import json
import os
import sys
import time
import urllib.parse
import uuid

from experiments import commit_without_reading_acknowledgment, context, record
from fixture import ROOT, private_json


def discover_operations(items, namespace):
    operations = {}
    for item in items:
        try:
            payload = json.loads(item["Name"])
        except (KeyError, TypeError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict) or payload.get("namespace") != namespace:
            continue
        operation_id = payload.get("operationId")
        if not isinstance(operation_id, str) or not operation_id or payload.get("kind") not in ["put", "delete"]:
            continue
        if operation_id in operations and operations[operation_id] != payload:
            raise ValueError("Conflicting payloads share one operation identifier")
        operations[operation_id] = payload
    return operations


def measure_privacy(alice, bob, playlist_id, payload):
    route = "/Items/" + playlist_id
    owner_status, _, owner_body = alice.request("GET", route)
    other_status, _, other_body = bob.request("GET", route)
    owner_exact = owner_status == 200 and json.loads(owner_body).get("Name") == payload
    try:
        other_document = json.loads(other_body)
    except (ValueError, UnicodeDecodeError):
        other_document = None
    exposed = (payload.encode() in other_body
               or isinstance(other_document, dict) and other_document.get("Name") == payload)
    assert owner_exact, "Owner must read the exact stored payload"
    assert other_status == 404 and not exposed, "Other user must be denied without the payload"
    return {"route": "/Items/{samePlaylistId}", "ownerStatus": owner_status,
            "ownerExactPayload": owner_exact, "otherUserStatus": other_status,
            "otherUserPayloadExposed": exposed, "otherUserResponseBytes": len(other_body),
            "sameObjectAndRoute": True}


def listing(client, **parameters):
    query = {"Recursive": "true", "IncludeItemTypes": "Playlist", "Limit": 128,
             "SortBy": "SortName", "SortOrder": "Ascending", **parameters}
    return client.json("GET", "/Items?" + urllib.parse.urlencode(query))


def create(client, name):
    return client.json("POST", "/Playlists", {"Name": name, "MediaType": "Audio", "IsPublic": False})["Id"]


def payload_for(namespace, operation):
    return json.dumps({"namespace": namespace, "operationId": operation,
                       "recordId": "synthetic-bookmark", "kind": "put", "note": "synthetic private note"})


def confidentiality():
    _, clients = context()
    payload = payload_for("Bookfin-t3-7fv1", uuid.uuid4().hex)
    playlist_id = create(clients["alice"], "Bookfin privacy control " + uuid.uuid4().hex)
    clients["alice"].json("POST", "/Playlists/" + playlist_id, {"Name": payload, "IsPublic": False})
    result = measure_privacy(clients["alice"], clients["bob"], playlist_id, payload)
    result["payloadSha256"] = hashlib.sha256(payload.encode()).hexdigest()
    record("playlist-confidentiality", result)
    private_json(ROOT / "protocol-state.json", {"privacyId": playlist_id, "payload": payload})


def objects():
    accounts, clients = context()
    alice, bob = clients["alice"], clients["bob"]
    namespace = "Bookfin-t3-7fv1-" + uuid.uuid4().hex
    operation = uuid.uuid4().hex
    pending_name = namespace + "-" + operation
    payload = payload_for(namespace, operation)
    before = {item["Id"] for item in listing(alice)["Items"]}
    request = {"Name": pending_name, "MediaType": "Audio", "IsPublic": False}
    commit_without_reading_acknowledgment(accounts["alice"]["token"], "/Playlists", request,
                                          lambda: any(item["Name"] == pending_name for item in listing(alice)["Items"]))
    first = next(item["Id"] for item in listing(alice)["Items"] if item["Name"] == pending_name)
    second = create(alice, pending_name)
    assert first != second
    pending_visible = alice.json("GET", "/Items/" + first)["Name"] == pending_name
    for playlist_id in [first, second]:
        alice.json("POST", "/Playlists/" + playlist_id, {"Name": payload, "IsPublic": False})
    duplicate_items = [item for item in listing(alice)["Items"] if item["Name"] == payload]
    operation_ids = set(discover_operations(duplicate_items, namespace))
    assert len(duplicate_items) == 2 and operation_ids == {operation}
    retry_status = alice.request("POST", "/Playlists/" + first, {"Name": payload, "IsPublic": False})[0]
    delete_status = alice.request("DELETE", "/Items/" + second)[0]
    stale_copy = create(alice, pending_name)
    alice.json("POST", "/Playlists/" + stale_copy, {"Name": payload, "IsPublic": False})
    after_cleanup_duplicates = [item for item in listing(alice)["Items"] if item["Name"] == payload]
    assert retry_status == delete_status == 204 and len(after_cleanup_duplicates) == 2
    stale_header_status = alice.request("POST", "/Playlists/" + first, {"Name": payload},
                                       headers={"If-Match": '"not-the-current-revision"'})[0]
    assert stale_header_status == 204
    bob_write = bob.request("POST", "/Playlists/" + first, {"Name": "not permitted"})[0]
    anonymous = type(alice)().request("GET", "/Items/" + first)[0]
    assert bob_write == 404 and anonymous == 401
    size_results = []
    for size in [240, 256, 1024, 65536]:
        status, _, body = alice.request("POST", "/Playlists", {"Name": "s" * size, "IsPublic": False})
        size_results.append({"createNameBytes": size, "status": status})
        if status == 200:
            alice.json("DELETE", "/Items/" + json.loads(body)["Id"])
    for size in [65536, 262144]:
        large_payload = json.dumps({"namespace": namespace, "note": "x" * size})
        status = alice.request("POST", "/Playlists/" + first, {"Name": large_payload})[0]
        exact = alice.json("GET", "/Items/" + first)["Name"] == large_payload
        size_results.append({"updatePayloadBytes": len(large_payload.encode()), "status": status, "exactRead": exact})
        assert status == 204 and exact
    alice.json("POST", "/Playlists/" + first, {"Name": payload})
    ordinary_list = listing(alice)
    assert first in {item["Id"] for item in ordinary_list["Items"]}
    ordinary_name_bytes = next(len(item["Name"].encode()) for item in ordinary_list["Items"] if item["Id"] == first)
    renamed = create(alice, namespace + "-rename")
    alice.json("POST", "/Playlists/" + renamed, {"Name": payload, "IsPublic": False})
    rename_status = alice.request("POST", "/Playlists/" + renamed, {"Name": "My renamed playlist"})[0]
    renamed_payload_lost = alice.json("GET", "/Items/" + renamed)["Name"] != payload
    assert rename_status == 204 and renamed_payload_lost
    shared = create(alice, namespace + "-sharing")
    alice.json("POST", "/Playlists/" + shared, {"Name": payload, "IsPublic": False})
    share_status = alice.request("POST", "/Playlists/" + shared, {"IsPublic": True})[0]
    shared_status, _, shared_body = bob.request("GET", "/Items/" + shared)
    assert share_status == 204 and shared_status == 200 and json.loads(shared_body)["Name"] == payload
    alice.json("POST", "/Playlists/" + shared, {"IsPublic": False})
    assert bob.request("GET", "/Items/" + shared)[0] == 404
    own_delete_without_content_permission = alice.request("DELETE", "/Items/" + renamed)[0]
    deleted_object_read = alice.request("GET", "/Items/" + renamed)[0]
    assert own_delete_without_content_permission == 204 and deleted_object_read == 404
    metadata_status = alice.request("POST", "/Items/" + first, {
        "Id": first, "Name": "Synthetic metadata edit", "Overview": "Synthetic alternate payload"})[0]
    assert metadata_status == 403
    assert alice.json("GET", "/Items/" + first)["Name"] == payload
    offline_operations = [uuid.uuid4().hex, uuid.uuid4().hex]
    offline_payloads = [payload_for(namespace, operation_id) for operation_id in offline_operations]
    offline_objects = [create(alice, namespace + "-offline-a"), create(alice, namespace + "-offline-b")]
    for playlist_id, offline_payload in zip(offline_objects, offline_payloads):
        alice.json("POST", "/Playlists/" + playlist_id, {"Name": offline_payload, "IsPublic": False})
    discovered = discover_operations(listing(alice)["Items"], namespace)
    assert set(offline_operations).issubset(discovered)
    record("playlist-objects", {
        "lostAck": {"realPostResponseBytesRead": 0, "independentlyWitnessed": True,
                    "physicalObjectsAfterRetry": 2, "logicalOperationIds": len(operation_ids),
                    "objectsAfterDuplicateCleanupAndDelayedRetry": len(after_cleanup_duplicates)},
        "publication": {"pendingNameVisibleBeforePayload": pending_visible, "repeatPayloadUpdateStatus": retry_status,
                        "staleIfMatchUpdateStatus": stale_header_status, "atomicLargeCreateProven": False},
        "permissions": {"otherUserUpdate": bob_write, "anonymousPayloadRead": anonymous,
                        "ownerDeleteWithContentDeletionDisabled": own_delete_without_content_permission,
                        "ownerReadAfterDeletion": deleted_object_read,
                        "ownerGenericMetadataUpdate": metadata_status},
        "offlineIndependentOperations": {"published": 2, "discovered": 2,
                                         "currentRecordConflictPolicyImplemented": False},
        "sizes": size_results, "maximumSizeProven": False,
        "coexistence": {"unfilteredPlaylistListingIncludesObject": True, "displayedPayloadNameBytes": ordinary_name_bytes,
                        "ordinaryRenameStatus": rename_status, "renameOverwritesPayload": renamed_payload_lost,
                        "explicitPublicToggleStatus": share_status, "bobReadAfterExplicitPublicToggle": shared_status,
                        "publicToggleExposesSyntheticPayload": True, "privateRestoredBobStatus": 404,
                        "realOtherClientUiExecuted": False},
        "createdObjects": len({item["Id"] for item in listing(alice)["Items"]} - before),
    })
    state = json.loads((ROOT / "protocol-state.json").read_text())
    state.update(namespace=namespace, journalId=first, journalPayload=payload)
    private_json(ROOT / "protocol-state.json", state)


def paging():
    _, clients = context()
    alice = clients["alice"]
    prefix = "BookfinPaging" + uuid.uuid4().hex
    identifiers = [create(alice, prefix + suffix) for suffix in ["A", "B", "C", "D"]]
    query = {"SearchTerm": prefix, "Limit": 2}
    page_one = listing(alice, **query, StartIndex=0)
    assert [item["Id"] for item in page_one["Items"]] == identifiers[:2]
    alice.json("DELETE", "/Items/" + identifiers[0])
    page_two = listing(alice, **query, StartIndex=2)
    received = {item["Id"] for item in page_one["Items"] + page_two["Items"]}
    assert identifiers[2] not in received and identifiers[3] in received
    fresh = listing(alice, SearchTerm=prefix)
    assert {item["Id"] for item in fresh["Items"]} == set(identifiers[1:])
    next_scan_page_one = listing(alice, **query, StartIndex=0)
    assert [item["Id"] for item in next_scan_page_one["Items"]] == identifiers[1:3]
    insertion = create(alice, prefix + "AA")
    after_insertion = listing(alice, SearchTerm=prefix)
    assert [item["Id"] for item in after_insertion["Items"]] == [insertion, *identifiers[1:]]
    next_scan_page_two = listing(alice, **query, StartIndex=2)
    repeated_ids = ({item["Id"] for item in next_scan_page_one["Items"]}
                    & {item["Id"] for item in next_scan_page_two["Items"]})
    assert repeated_ids == {identifiers[2]}
    record("playlist-paging", {"pageSize": 2, "initialObjects": 4,
                              "deleteBeforeSecondPage": True, "liveObjectSkipped": True,
                              "pageOneTotal": page_one["TotalRecordCount"],
                              "pageTwoTotal": page_two["TotalRecordCount"],
                              "freshScanAfterQuiescenceFindsAll": True,
                              "insertionBeforeSecondPageDuplicatesLiveObject": True,
                              "snapshotOrChangeCursorProven": False})
    for playlist_id in [*identifiers[1:], insertion]:
        alice.json("DELETE", "/Items/" + playlist_id)


def scan():
    _, clients = context()
    state = json.loads((ROOT / "protocol-state.json").read_text())
    previous = next(task for task in clients["admin"].json("GET", "/ScheduledTasks") if task["Key"] == "RefreshLibrary")
    previous_end = previous.get("LastExecutionResult", {}).get("EndTimeUtc")
    clients["admin"].json("POST", "/Library/Refresh")
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        tasks = clients["admin"].json("GET", "/ScheduledTasks")
        task = next(task for task in tasks if task["Key"] == "RefreshLibrary")
        execution = task.get("LastExecutionResult", {})
        if (task["State"] == "Idle" and execution.get("EndTimeUtc") != previous_end
                and execution.get("Status") == "Completed"):
            break
        time.sleep(0.5)
    else:
        raise AssertionError("Library scan exceeded its 90-second measurement window")
    result = measure_privacy(clients["alice"], clients["bob"], state["journalId"], state["journalPayload"])
    result["libraryScanCompleted"] = True
    result["completedScanStartUtc"] = execution["StartTimeUtc"]
    result["completedScanEndUtc"] = execution["EndTimeUtc"]
    result["upgradeTested"] = False
    record("playlist-scan", result)


def restarted():
    _, clients = context()
    state = json.loads((ROOT / "protocol-state.json").read_text())
    result = measure_privacy(clients["alice"], clients["bob"], state["journalId"], state["journalPayload"])
    result["sameServerIdentityChecked"] = True
    result["cleanRestartOnly"] = True
    result["upgradeTested"] = False
    record("playlist-protocol-restart", result)


if __name__ == "__main__":
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise SystemExit("Run through nix develop ./tool/research/sync")
    commands = {"confidentiality": confidentiality, "objects": objects, "paging": paging,
                "scan": scan, "restarted": restarted}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        raise SystemExit("Use confidentiality, objects, paging, scan, or restarted")
    commands[sys.argv[1]]()
