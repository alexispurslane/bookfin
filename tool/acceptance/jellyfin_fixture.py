import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import time
import urllib.parse


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "research/sync"))
import fixture


def prepare_acceptance():
    os.umask(0o077)
    root = fixture.ROOT
    marker = json.loads((root / "fixture.json").read_text())
    public = fixture.Api().json("GET", "/System/Info/Public")
    if marker.get("serverId") != public["Id"]:
        raise RuntimeError("Refusing an unrecognized server")
    accounts = json.loads((root / "accounts.json").read_text())
    admin = fixture.Api(accounts["admin"]["token"])
    manifest_file = root / "app-acceptance.json"
    if manifest_file.exists():
        raise RuntimeError("Acceptance already prepared; retain the existing private manifest")
    music = root / "media/music"
    music.mkdir(mode=0o700, exist_ok=True)
    shutil.copyfile(root / "media/public/Work/Recording B/other-narrator.m4b", music / "non-book.m4a")
    query = urllib.parse.urlencode({"name": "Synthetic music", "collectionType": "music", "refreshLibrary": "false"})
    existing = admin.json("GET", "/Library/VirtualFolders")
    if not any(library["Name"] == "Synthetic music" for library in existing):
        admin.json("POST", "/Library/VirtualFolders?" + query, {"LibraryOptions": {
            "PathInfos": [{"Path": str(music)}], "EnableRealtimeMonitor": False,
            "EnableInternetProviders": False, "AutomaticRefreshIntervalDays": 0,
        }})
    libraries = admin.json("GET", "/Library/VirtualFolders")
    music_id = next(library["ItemId"] for library in libraries if library["Name"] == "Synthetic music")
    for name in ["alice", "bob"]:
        policy = admin.json("GET", f'/Users/{accounts[name]["id"]}')["Policy"]
        if music_id not in policy["EnabledFolders"]:
            policy["EnabledFolders"].append(music_id)
        admin.json("POST", f'/Users/{accounts[name]["id"]}/Policy', policy)
    admin.json("POST", "/Library/Refresh")
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        items = admin.json("GET", "/Items?recursive=true&includeItemTypes=AudioBook,Book,Audio&fields=Path,MediaSources,Chapters")["Items"]
        if len(items) == 7 and all(item["Type"] == "Book" or item.get("MediaSources") for item in items):
            break
        time.sleep(0.5)
    else:
        raise RuntimeError("The seven synthetic sources did not scan")
    sources = {}
    for item in items:
        path = Path(item["Path"])
        if not path.is_relative_to(root / "media"):
            raise RuntimeError("Unexpected media outside the disposable fixture")
        label = path.relative_to(root / "media").as_posix()
        sources[label] = {"itemId": item["Id"], "path": str(path),
                          "length": path.stat().st_size,
                          "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        if label.startswith("public/"):
            details = admin.json("GET", f'/Items/{item["Id"]}')
            details["Name"] = "Synthetic Work"
            admin.json("POST", f'/Items/{item["Id"]}', details)
    fixture.private_json(manifest_file, {
        "origin": fixture.ORIGIN, "serverId": public["Id"], "version": public["Version"],
        "libraries": {library["Name"]: library["ItemId"] for library in libraries},
        "sources": sources,
    })
    print("Prepared seven synthetic sources, matching titles, and a non-book library")


if __name__ == "__main__":
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise SystemExit("Run through the pinned sync Nix shell")
    prepare_acceptance()
