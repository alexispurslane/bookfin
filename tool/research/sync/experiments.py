import concurrent.futures
import copy
import datetime
import hashlib
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import uuid

from fixture import Api, ORIGIN, ROOT, private_json


EVIDENCE = Path(__file__).parent / "evidence"


def context():
    marker = json.loads((ROOT / "fixture.json").read_text())
    public = Api().json("GET", "/System/Info/Public")
    assert public["Id"] == marker["serverId"], "Refusing an unrecognized server"
    accounts = json.loads((ROOT / "accounts.json").read_text())
    clients = {name: Api(account["token"]) for name, account in accounts.items()}
    for name in ["alice", "bob"]:
        user = clients[name].json("GET", "/Users/Me")
        assert user["Name"] == "research-" + name and user["Policy"]["IsAdministrator"] is False
    return accounts, clients


def record(phase, observations):
    EVIDENCE.mkdir(exist_ok=True)
    result = {"evidenceClass": "disposable-official-binary-runtime", "origin": ORIGIN,
              "observedAtUtc": datetime.datetime.now(datetime.UTC).isoformat(),
              "phase": phase, "observations": observations}
    (EVIDENCE / f"{phase}.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"phase": phase, "observations": len(observations), "evidence": f"evidence/{phase}.json"}))


def commit_without_reading_acknowledgment(token, path, payload, witnessed):
    body = json.dumps(payload).encode()
    headers = (f"POST {path} HTTP/1.1\r\nHost: 127.0.0.1:7364\r\n"
               f'Authorization: MediaBrowser Client="Bookfin disposable research", Device="Synthetic", DeviceId="ta-qobz", Version="1", Token="{token}"\r\n'
               f"Content-Type: application/json\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n")
    with socket.create_connection(("127.0.0.1", 7364), timeout=5) as connection:
        connection.sendall(headers.encode() + body)
        for attempt in range(30):
            if witnessed():
                return
            time.sleep(0.1)
    raise AssertionError("The write without a read acknowledgment was not independently witnessed")


def catalog():
    accounts, clients = context()
    alice, bob, admin = clients["alice"], clients["bob"], clients["admin"]
    fields = "Path,ParentId,MediaSources,Chapters,ProviderIds"
    alice_items = alice.json("GET", f"/Items?recursive=true&includeItemTypes=AudioBook,Book,Folder&fields={fields}")["Items"]
    bob_items = bob.json("GET", f"/Items?recursive=true&includeItemTypes=AudioBook,Book,Folder&fields={fields}")["Items"]
    audio = [item for item in alice_items if item["Type"] == "AudioBook"]
    hidden = next(item for item in audio if "private/Hidden" in item["Path"])
    first = next(item for item in audio if item["Name"] == "z-first")
    assert [chapter["StartPositionTicks"] for chapter in first["Chapters"]] == [0, 900000000]
    assert hidden["Id"] not in {item["Id"] for item in bob_items}
    assert len(audio) == 5 and len([item for item in bob_items if item["Type"] == "AudioBook"]) == 4
    statuses = {
        "unauthenticatedCatalog": Api().request("GET", "/Items")[0],
        "unauthenticatedDownload": Api().request("GET", f'/Items/{first["Id"]}/Download')[0],
        "bobHiddenItem": bob.request("GET", f'/Items/{hidden["Id"]}')[0],
        "bobHiddenDownload": bob.download(hidden["Id"], bob.json("GET", "/Users/Me")["Policy"])[0],
        "aliceMissingItem": alice.request("GET", "/Items/" + "f" * 32)[0],
        "aliceMissingDownload": alice.download("f" * 32, alice.json("GET", "/Users/Me")["Policy"])[0],
        "bobCannotImpersonateAlice": bob.request("GET", "/Items?userId=" + accounts["alice"]["id"])[0],
    }
    assert statuses == {"unauthenticatedCatalog": 401, "unauthenticatedDownload": 401,
                        "bobHiddenItem": 404, "bobHiddenDownload": 404,
                        "aliceMissingItem": 404, "aliceMissingDownload": 404,
                        "bobCannotImpersonateAlice": 403}, statuses
    status, headers, body = alice.download(first["Id"], alice.json("GET", "/Users/Me")["Policy"])
    source = Path(first["Path"]).read_bytes()
    assert status == 206 and body == source[:32]
    assert headers["Content-Range"] == f"bytes 0-31/{len(source)}"
    second_status, second_headers, second_body = alice.request("GET", f'/Items/{first["Id"]}/Download', headers={"Range": "bytes=32-63"})
    assert second_status == 206 and second_body == source[32:64]
    policy = admin.json("GET", f'/Users/{accounts["alice"]["id"]}')["Policy"]
    denied = copy.deepcopy(policy)
    denied["EnableContentDownloading"] = False
    try:
        admin.json("POST", f'/Users/{accounts["alice"]["id"]}/Policy', denied)
        current = alice.json("GET", "/Users/Me")["Policy"]
        assert current["EnableContentDownloading"] is False
        disabled_status = alice.request("GET", f'/Items/{first["Id"]}/Download', headers={"Range": "bytes=0-31"})[0]
        assert disabled_status == 403, disabled_status
        try:
            alice.download(first["Id"], current)
            raise AssertionError("The client did not block the denied download")
        except PermissionError:
            pass
    finally:
        admin.json("POST", f'/Users/{accounts["alice"]["id"]}/Policy', policy)
    parts = alice.json("GET", f'/Items?parentId={first["ParentId"]}&sortBy=ParentIndexNumber,IndexNumber&sortOrder=Ascending&fields={fields}')["Items"]
    assert [item["Name"] for item in parts] == ["z-first", "a-second", "m-third"]
    edition_b = next(item for item in audio if item["Name"] == "other-narrator")
    ebook = next(item for item in alice_items if item["Type"] == "Book")
    folder_a = next(item for item in alice_items if item["Id"] == first["ParentId"])
    assert folder_a["ParentId"] == ebook["ParentId"] == edition_b["ParentId"]
    ebook_status, ebook_headers, ebook_body = alice.download(ebook["Id"], policy)
    assert ebook_status == 206 and ebook_body == Path(ebook["Path"]).read_bytes()[:32]
    playback = {"ItemId": first["Id"], "PositionTicks": 600000000,
                "CanSeek": True, "PlayMethod": "DirectPlay", "IsPaused": False}
    original_config = admin.json("GET", "/System/Configuration")
    changed_config = copy.deepcopy(original_config)
    changed_config["MinAudiobookResume"] = 0
    changed_config["MaxAudiobookResume"] = 0
    try:
        admin.json("POST", "/System/Configuration", changed_config)
        alice.json("POST", "/Sessions/Playing", playback)
        alice.json("POST", "/Sessions/Playing/Progress", playback)
        alice.json("POST", "/Sessions/Playing/Stopped", playback)
        alice_position = alice.json("GET", f'/UserItems/{first["Id"]}/UserData')["PlaybackPositionTicks"]
        bob_position = bob.json("GET", f'/UserItems/{first["Id"]}/UserData')["PlaybackPositionTicks"]
        assert alice_position == 600000000 and bob_position == 0, (alice_position, bob_position)
    finally:
        admin.json("POST", "/System/Configuration", original_config)
    sample = []
    for item in alice_items:
        sample.append({key: item[key] for key in ["Id", "Name", "Type", "ParentId", "IndexNumber", "ParentIndexNumber", "Album", "Artists", "ProviderIds"] if key in item})
        if "Path" in item:
            sample[-1]["SyntheticRelativePath"] = str(Path(item["Path"]).relative_to(ROOT / "media"))
        sample[-1]["mediaSourceCount"] = len(item.get("MediaSources", []))
        sample[-1]["chapters"] = [{"Name": chapter.get("Name"), "StartPositionTicks": chapter["StartPositionTicks"]} for chapter in item.get("Chapters", [])]
    sanitized_items = []
    for item in alice_items:
        sanitized = {key: copy.deepcopy(item[key]) for key in ["Id", "Name", "Type", "ParentId", "IndexNumber", "ParentIndexNumber", "Album", "Artists", "ProviderIds", "RunTimeTicks", "MediaSources", "Chapters", "Path"] if key in item}
        if "Path" in sanitized:
            sanitized["Path"] = "/synthetic/" + str(Path(sanitized["Path"]).relative_to(ROOT / "media"))
        for media_source in sanitized.get("MediaSources", []):
            if "Path" in media_source:
                media_source["Path"] = "/synthetic/" + str(Path(media_source["Path"]).relative_to(ROOT / "media"))
        sanitized_items.append(sanitized)
    EVIDENCE.mkdir(exist_ok=True)
    (EVIDENCE / "catalog-dtos.json").write_text(json.dumps({
        "evidenceClass": "disposable-runtime-dtos-with-rewritten-path-prefixes",
        "items": sanitized_items, "bobVisibleItemIds": [item["Id"] for item in bob_items],
        "expectedExplicitGrouping": {"audioEditionA": [item["Id"] for item in parts],
                                     "audioEditionB": [edition_b["Id"]], "ebookEdition": ebook["Id"]},
        "warning": "Expected grouping is the synthetic fixture's authored relationship, not a claim that Jellyfin or Bookfin inferred it. Run the catalog mapper against these DTOs before closing boo-2cgp."
    }, indent=2) + "\n")
    private_json(ROOT / "catalog-state.json", {"itemId": first["Id"], "position": alice_position})
    record("catalog", {"authorizationStatuses": statuses,
                        "range": {"status": status, "bytes": len(body), "contentRange": headers["Content-Range"], "secondRangeStatus": second_status, "bytesMatchSeed": True},
                        "disabledDownloadStatus": disabled_status,
                        "missingPermission": "client guard tested without network; this server always returns the flag",
                        "fileBypassRequests": 0, "ordinaryAudioCounts": {"alice": 5, "bob": 4},
                        "orderedParts": [{"name": item["Name"], "disc": item["ParentIndexNumber"], "track": item["IndexNumber"], "id": item["Id"]} for item in parts],
                        "pairing": {"audioEditionA": [item["Id"] for item in parts], "audioEditionB": [edition_b["Id"]], "ebookEdition": ebook["Id"], "sharedWorkAncestor": ebook["ParentId"], "ebookRangeStatus": ebook_status, "automaticPairingDeclaredByServer": False, "applicationMapperExecuted": False},
                        "playback": {"aliceTicks": alice_position, "bobTicks": bob_position, "minAudiobookResumeMinutesDuringProbe": 0, "maxAudiobookResumeMinutesDuringProbe": 0, "originalMinAudiobookResumeMinutes": original_config["MinAudiobookResume"], "originalMaxAudiobookResumeMinutes": original_config["MaxAudiobookResume"]},
                        "actualCatalogDtos": sample})


def storage():
    accounts, clients = context()
    alice, bob = clients["alice"], clients["bob"]
    user_id = accounts["alice"]["id"]
    enhanced_root = ROOT / "data/plugins/configurations/Jellyfin.Plugin.JellyfinEnhanced"
    user_directory = enhanced_root / user_id.replace("-", "").lower()
    endpoint = f"/JellyfinEnhanced/user-settings/{user_id}/bookmark.json"
    initial = {"directoryExists": user_directory.exists(), "bookmarkExists": (user_directory / "bookmark.json").exists(), "settingsExists": (user_directory / "settings.json").exists()}
    empty = alice.json("GET", endpoint)
    after_bookmark = {"directoryExists": user_directory.exists(), "bookmarkExists": (user_directory / "bookmark.json").exists(), "settingsExists": (user_directory / "settings.json").exists()}
    alice.json("GET", f"/JellyfinEnhanced/user-settings/{user_id}/settings.json")
    after_settings = {"directoryExists": user_directory.exists(), "bookmarkExists": (user_directory / "bookmark.json").exists(), "settingsExists": (user_directory / "settings.json").exists()}
    bob_directory = enhanced_root / accounts["bob"]["id"].replace("-", "").lower()
    if bob_directory.exists() and not any(bob_directory.iterdir()):
        bob_directory.rmdir()
    bob_before = bob_directory.exists()
    bob.json("GET", f'/JellyfinEnhanced/user-settings/{accounts["bob"]["id"]}/bookmark.json')
    bob_after_get = {"directoryExists": bob_directory.exists(), "bookmarkExists": (bob_directory / "bookmark.json").exists()}
    assert not bob_before and bob_after_get == {"directoryExists": True, "bookmarkExists": False}
    unauthenticated = Api().request("GET", endpoint)[0]
    cross_user = {method: bob.request(method, endpoint, {"Bookmarks": {}} if method == "POST" else None)[0] for method in ["GET", "POST"]}
    cross_add = bob.request("POST", endpoint + "/add", {"ItemId": "synthetic"})[0]
    unknown = alice.request("POST", f"/JellyfinEnhanced/user-settings/{user_id}/bookfin.json", {"records": []})[0]
    assert unauthenticated == 401 and cross_user == {"GET": 403, "POST": 403} and cross_add == 403 and unknown == 404
    alice.json("POST", endpoint, {"Bookmarks": {}, "BookfinRecords": {"unexpected": "must not survive"}})
    typed = alice.json("GET", endpoint)
    assert "BookfinRecords" not in typed and "bookfinRecords" not in typed
    item_id = json.loads((ROOT / "catalog-state.json").read_text())["itemId"]
    payload = {"ItemId": item_id, "Name": "Synthetic only", "Label": "one user action", "Timestamp": 60.0, "MediaType": "AudioBook"}
    alice.json("POST", endpoint, {"Bookmarks": {}})
    commit_without_reading_acknowledgment(accounts["alice"]["token"], endpoint + "/add", payload,
                                        lambda: any(alice.json("GET", endpoint).get(key) for key in ["Bookmarks", "bookmarks"]))
    stale = alice.json("GET", endpoint)
    first_key = next(key for key in stale if key.lower() == "bookmarks")
    first_add = {"id": next(iter(stale[first_key]))}
    second_add = alice.json("POST", endpoint + "/add", payload)
    duplicate_document = alice.json("GET", endpoint)
    bookmarks_key = next(key for key in duplicate_document if key.lower() == "bookmarks")
    assert first_add["id"] != second_add["id"] and len(duplicate_document[bookmarks_key]) == 2
    alice.json("POST", endpoint, stale)
    after_stale = alice.json("GET", endpoint)[bookmarks_key]
    assert first_add["id"] in after_stale and second_add["id"] not in after_stale
    deleted = alice.request("DELETE", endpoint + "/" + first_add["id"])[0]
    repeated_delete = alice.request("DELETE", endpoint + "/" + first_add["id"])[0]
    assert deleted == 200 and repeated_delete == 404 and not alice.json("GET", endpoint)[bookmarks_key]
    alice.json("POST", endpoint, stale)
    assert first_add["id"] in alice.json("GET", endpoint)[bookmarks_key]
    alice.json("POST", endpoint, {"Bookmarks": {}})
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        additions = list(pool.map(lambda index: Api(accounts["alice"]["token"]).json("POST", endpoint + "/add", dict(payload, Label=f"parallel {index}")), range(8)))
    assert len(alice.json("GET", endpoint)[bookmarks_key]) == 8
    big = alice.json("POST", endpoint + "/add", dict(payload, Label="x" * 65536))
    big_document = alice.json("GET", endpoint)
    label_key = next(key for key in big_document[bookmarks_key][big["id"]] if key.lower() == "label")
    assert len(big_document[bookmarks_key][big["id"]][label_key]) == 65536
    enhanced_bytes = (user_directory / "bookmark.json").stat().st_size
    scope = "bookfin-ta-qobz-synthetic"
    prefs_path = f"/DisplayPreferences/{scope}?client=bookfin-ta-qobz"
    prefs = alice.json("GET", prefs_path)
    alice.json("POST", prefs_path, dict(prefs, CustomPrefs={}))
    first_snapshot = alice.json("GET", prefs_path)
    second_snapshot = copy.deepcopy(first_snapshot)
    first_snapshot["CustomPrefs"]["record-a"] = "A"
    second_snapshot["CustomPrefs"]["record-b"] = "B"
    commit_without_reading_acknowledgment(accounts["alice"]["token"], prefs_path, first_snapshot,
                                        lambda: alice.json("GET", prefs_path)["CustomPrefs"].get("record-a") == "A")
    alice.json("POST", prefs_path, second_snapshot)
    lost_edit = alice.json("GET", prefs_path)["CustomPrefs"]
    assert "record-b" in lost_edit and "record-a" not in lost_edit
    alice.json("POST", prefs_path, first_snapshot)
    assert "record-a" in alice.json("GET", prefs_path)["CustomPrefs"] and "record-b" not in alice.json("GET", prefs_path)["CustomPrefs"]
    alice.json("POST", prefs_path, dict(prefs, CustomPrefs={}))
    alice.json("POST", prefs_path, first_snapshot)
    assert "record-a" in alice.json("GET", prefs_path)["CustomPrefs"]
    prefs_cross_get = bob.request("GET", prefs_path + "&userId=" + user_id)[0]
    prefs_cross_post = bob.request("POST", prefs_path + "&userId=" + user_id, prefs)[0]
    assert prefs_cross_get == prefs_cross_post == 403
    assert "record-a" not in bob.json("GET", prefs_path)["CustomPrefs"]
    isolated_scope = alice.json("GET", "/DisplayPreferences/bookfin-isolated?client=bookfin-ta-qobz")
    alice.json("POST", "/DisplayPreferences/bookfin-isolated?client=bookfin-ta-qobz", dict(isolated_scope, CustomPrefs={"separate-record": "kept"}))
    assert alice.json("GET", prefs_path)["CustomPrefs"]["record-a"] == "A"
    paths = json.loads((ROOT.parents[0] / "openapi.json").read_text())["paths"]
    preference_routes = sorted(path for path in paths if "DisplayPreferences" in path)
    prefs_large = dict(prefs, CustomPrefs={"large": "x" * 65536})
    alice.json("POST", prefs_path, prefs_large)
    assert len(alice.json("GET", prefs_path)["CustomPrefs"]["large"]) == 65536
    compare_and_swap_status = alice.request("POST", prefs_path, prefs_large, headers={"If-Match": '"definitely-stale"'})[0]
    assert compare_and_swap_status == 204
    cross_delete = bob.request("DELETE", endpoint + "/" + big["id"])[0]
    assert cross_delete == 403
    def row_counts():
        with sqlite3.connect(f"file:{ROOT / 'data/data/jellyfin.db'}?mode=ro", uri=True) as database:
            return {name: database.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
                    for (name,) in database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%DisplayPreferences%'")}
    before_scope_get = row_counts()
    new_scope = "/DisplayPreferences/" + str(uuid.uuid4()) + "?client=bookfin-ta-qobz"
    fresh_scope = alice.json("GET", new_scope)
    after_scope_get = row_counts()
    alice.json("POST", new_scope, dict(fresh_scope, CustomPrefs={}))
    after_scope_clear = row_counts()
    assert after_scope_get["DisplayPreferences"] == before_scope_get["DisplayPreferences"] + 1
    assert after_scope_get["ItemDisplayPreferences"] == before_scope_get["ItemDisplayPreferences"] + 1
    assert after_scope_clear == after_scope_get
    with sqlite3.connect(f"file:{ROOT / 'data/data/jellyfin.db'}?mode=ro", uri=True) as database:
        preference_tables = {name: database.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
                             for (name,) in database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%DisplayPreferences%'")}
    private_json(ROOT / "storage-state.json", {"prefsPath": prefs_path, "bookmarkId": big["id"], "bookmarksKey": bookmarks_key, "labelKey": label_key})
    record("storage", {"readSideEffects": {"before": initial, "afterBookmarkGet": after_bookmark, "afterSettingsGet": after_settings, "freshBobDirectoryBeforeBookmarkGet": bob_before, "freshBobAfterBookmarkGet": bob_after_get, "emptyBobDirectoryRemovedBeforeMeasurement": True},
                        "authorization": {"unauthenticated": unauthenticated, "enhancedCrossUser": cross_user, "enhancedCrossUserAdd": cross_add, "enhancedCrossUserDelete": cross_delete, "prefsCrossUserGet": prefs_cross_get, "prefsCrossUserPost": prefs_cross_post},
                        "enhanced": {"unknownDocumentStatus": unknown, "unknownTopLevelFieldRetained": False, "lostAcknowledgmentSamePayloadCount": 2, "staleSnapshotRemovedOtherAdd": True, "firstDeleteStatus": deleted, "repeatedDeleteStatus": repeated_delete, "staleSaveResurrectedDeletion": True, "parallelAdds": len(additions), "parallelAddsPreserved": True, "acceptedLabelBytes": 65536, "bookmarkDocumentDiskBytes": enhanced_bytes, "maximumAcceptedSizeProven": False, "retainedDeletionMarker": False},
                        "customPreferences": {"staleSnapshotLostIndependentEdit": True, "staleRetryLostLaterEdit": True, "deleteThenStaleRetryResurrected": True, "separateScopesCoexist": True, "arbitraryScopeDiscoveryRoutes": preference_routes, "acceptedValueBytes": 65536, "maximumAcceptedSizeProven": False, "databasePreferenceRows": preference_tables, "staleIfMatchPostStatus": compare_and_swap_status, "scopeGetRowsBefore": before_scope_get, "scopeGetRowsAfter": after_scope_get, "emptyPostRowsAfter": after_scope_clear},
                        "lostAcknowledgmentMethod": "Send a real HTTP POST through a socket, independently witness committed state, close without reading any response bytes, then retry",
                        "retention": "No time-based retention, replica expiry, tombstone collection, or upper server bound established"})


def playlists():
    accounts, clients = context()
    alice, bob = clients["alice"], clients["bob"]
    operation = str(uuid.uuid4())
    label = "Bookfin disposable " + operation
    def create(name):
        return Api(accounts["alice"]["token"]).json("POST", "/Playlists", {"Name": name, "MediaType": "Audio", "IsPublic": False})["Id"]
    first = create(label)
    duplicate = create(label)
    assert first != duplicate
    cross_get = bob.request("GET", "/Playlists/" + first)[0]
    cross_write = bob.request("POST", "/Playlists/" + first, {"Name": "must not change"})[0]
    cross_delete = bob.request("DELETE", "/Items/" + first)[0]
    assert cross_get == cross_write == cross_delete == 404
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        independent = list(pool.map(create, [label + "-a", label + "-b"]))
    assert len(set(independent)) == 2
    large_name = json.dumps({"bookfinSyntheticOperation": operation, "note": "x" * 65536})
    alice.json("POST", "/Playlists/" + first, {"Name": large_name, "IsPublic": False})
    assert alice.json("GET", "/Items/" + first)["Name"] == large_name
    discovered = alice.json("GET", "/Items?recursive=true&includeItemTypes=Playlist")["Items"]
    bob_discovered = bob.json("GET", "/Items?recursive=true&includeItemTypes=Playlist")["Items"]
    assert {first, duplicate, *independent}.issubset({item["Id"] for item in discovered})
    assert first not in {item["Id"] for item in bob_discovered}
    delete_status = alice.request("DELETE", "/Items/" + duplicate)[0]
    assert delete_status == 204
    replayed = create(label)
    assert alice.request("GET", "/Items/" + replayed)[0] == 200
    private_json(ROOT / "playlist-state.json", {"id": first, "nameHash": hashlib.sha256(large_name.encode()).hexdigest(), "cleanup": [first, replayed, *independent]})
    record("playlists", {"authorization": {"crossUserRead": cross_get, "crossUserWrite": cross_write, "crossUserDelete": cross_delete},
                          "privateOwnerCanCreateDiscoverUpdateDelete": True,
                          "independentConcurrentObjects": 2, "retryCreatedDistinctObjects": True,
                          "renamedPayloadBytes": len(large_name.encode()), "payloadRoundTrip": True,
                          "deleteStatus": delete_status, "staleCreateReintroducedOperation": True,
                          "boundedRetentionProtocolProven": False,
                          "suitability": "Promising app-owned discoverable storage; not rejected by snapshot counterexamples. Complete journal/single-writer protocol, paging under churn, retention fencing and client coexistence remain unproved. No transport selected."})


def read_side_effects():
    accounts, clients = context()
    user_id = accounts["bob"]["id"].replace("-", "").lower()
    directory = ROOT / "data/plugins/configurations/Jellyfin.Plugin.JellyfinEnhanced" / user_id
    if directory.exists() and not any(directory.iterdir()):
        directory.rmdir()
    assert not directory.exists(), "This one-shot phase needs Bob's untouched Enhanced documents"
    endpoint = "/JellyfinEnhanced/user-settings/" + user_id
    clients["bob"].json("GET", endpoint + "/bookmark.json")
    bookmark_read = {"directoryExists": directory.exists(), "bookmarkExists": (directory / "bookmark.json").exists(), "settingsExists": (directory / "settings.json").exists()}
    settings = clients["bob"].json("GET", endpoint + "/settings.json")
    settings_read = {"directoryExists": directory.exists(), "bookmarkExists": (directory / "bookmark.json").exists(), "settingsExists": (directory / "settings.json").exists()}
    assert bookmark_read == {"directoryExists": True, "bookmarkExists": False, "settingsExists": False}
    assert settings_read == {"directoryExists": True, "bookmarkExists": False, "settingsExists": True}
    settings["BookfinSyntheticNamespace"] = {"note": "must not become arbitrary storage"}
    clients["bob"].json("POST", endpoint + "/settings.json", settings)
    persisted = clients["bob"].json("GET", endpoint + "/settings.json")
    assert not any(key.lower() == "bookfinsyntheticnamespace" for key in persisted)
    record("read-side-effects", {"emptySyntheticBobDirectoryRemovedBeforeMeasurement": True,
                                  "before": {"directoryExists": False, "bookmarkExists": False, "settingsExists": False},
                                  "afterBookmarkGet": bookmark_read, "afterSettingsGet": settings_read,
                                  "settingsUnknownNamespaceRetained": False})


def provenance():
    accounts, clients = context()
    server = Path(os.environ["BOOKFIN_SYNC_SERVER"])
    enhanced = Path(os.environ["BOOKFIN_SYNC_ENHANCED"])
    plugins = clients["admin"].json("GET", "/Plugins")
    plugin = next(plugin for plugin in plugins if plugin["Name"] == "Jellyfin Enhanced")
    version_status, version_headers, version_body = Api().request("GET", "/JellyfinEnhanced/version")
    assert plugin["Version"] == "12.14.0.0" and plugin["Status"] == "Active"
    assert version_status == 200 and version_body.decode() == "12.14.0.0"
    binary = enhanced / "Jellyfin.Plugin.JellyfinEnhanced.dll"
    version_strings = subprocess.check_output(["/usr/bin/strings", str(binary)]).decode().splitlines()
    commit = "9bbf16c0de6662baeaa23e51c71505c15c560381"
    embedded_commit_strings = [line for line in version_strings if commit in line]
    assert embedded_commit_strings
    assets = {}
    for name in ["bookmarks/bookmarks.js", "config.js"]:
        status, headers, body = Api().request("GET", "/JellyfinEnhanced/js/enhanced/" + name)
        assert status == 200
        assets[name] = {"sha256": hashlib.sha256(body).hexdigest(), "bytes": len(body)}
    assert assets["bookmarks/bookmarks.js"]["sha256"] == "88ed2cb6310234be67ec2e6e9126772d7a1576d1377d61a47deba038fb42b497"
    assert assets["config.js"]["sha256"] == "f12788930e01c1459013b20be4fb1e13df165becf8c79addf13bcad57710c3d2"
    record("provenance", {"serverReportedVersion": Api().json("GET", "/System/Info/Public")["Version"],
                           "enhancedReportedVersion": version_body.decode(), "enhancedPluginStatus": plugin["Status"],
                           "serverDllSha256": hashlib.sha256((server / "jellyfin.dll").read_bytes()).hexdigest(),
                           "enhancedDllSha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                           "enhancedEmbeddedCommitStrings": embedded_commit_strings, "enhancedAssets": assets,
                           "python": sys.version.split()[0],
                           "ffmpeg": subprocess.check_output(["ffmpeg", "-version"]).decode().splitlines()[0],
                           "serverNixStorePath": str(server), "enhancedNixStorePath": str(enhanced),
                           "deployedProductionBackendCompared": False,
                           "independentRebuildOrAttestationVerified": False})


def after_restart():
    accounts, clients = context()
    alice = clients["alice"]
    storage_state = json.loads((ROOT / "storage-state.json").read_text())
    catalog_state = json.loads((ROOT / "catalog-state.json").read_text())
    playlist_state = json.loads((ROOT / "playlist-state.json").read_text())
    prefs = alice.json("GET", storage_state["prefsPath"])["CustomPrefs"]
    bookmark = alice.json("GET", f'/JellyfinEnhanced/user-settings/{accounts["alice"]["id"]}/bookmark.json')[storage_state["bookmarksKey"]]
    playlist_name = alice.json("GET", "/Items/" + playlist_state["id"])["Name"]
    position = alice.json("GET", f'/UserItems/{catalog_state["itemId"]}/UserData')["PlaybackPositionTicks"]
    assert len(prefs["large"]) == 65536
    assert len(bookmark[storage_state["bookmarkId"]][storage_state["labelKey"]]) == 65536
    assert hashlib.sha256(playlist_name.encode()).hexdigest() == playlist_state["nameHash"]
    assert position == catalog_state["position"]
    record("restart", {"sameServerIdentityAndOrdinaryTokensWork": True, "customPrefsLargeValueSurvives": True,
                        "enhancedBookmarksSurvive": True, "privatePlaylistPayloadSurvives": True,
                        "standardPlaybackPositionSurvivesTicks": position,
                        "restartKind": "authenticated clean shutdown followed by same pinned binary and same isolated directories",
                        "powerLossDurabilityProven": False, "upgradeCompatibilityProven": False})


if __name__ == "__main__":
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise SystemExit("Run through the pinned sync Nix shell")
    phases = {"catalog": catalog, "storage": storage, "playlists": playlists, "after-restart": after_restart,
              "read-side-effects": read_side_effects, "provenance": provenance}
    if len(sys.argv) != 2 or sys.argv[1] not in phases:
        raise SystemExit("Use catalog, storage, playlists, read-side-effects, provenance, or after-restart")
    phases[sys.argv[1]]()
