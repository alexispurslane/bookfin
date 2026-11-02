import hashlib
import json
from pathlib import Path


repository = Path(__file__).resolve().parents[2]
runtime = repository / ".cache/sync/runtime"
results = json.loads((runtime / "app-results.json").read_text())
manifest = json.loads((runtime / "app-acceptance.json").read_text())
pins = json.loads((repository / "tool/research/sync/sources.json").read_text())
accounts = json.loads((runtime / "accounts.json").read_text())
passwords = json.loads((runtime / "passwords.json").read_text())
if len(results["results"]) != 9 or any(not check["passed"] for check in results["results"].values()):
    raise RuntimeError("All nine live app checks must pass before publication")
if results["serverId"] != manifest["serverId"]:
    raise RuntimeError("Evidence belongs to a different fixture")
synthetic_sources = {}
for label, source in manifest["sources"].items():
    path = Path(source["path"])
    if not path.is_relative_to(runtime / "media"):
        raise RuntimeError("Refusing media outside this fixture")
    if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
        raise RuntimeError("Synthetic bytes were not restored after acceptance")
    synthetic_sources[label] = {key: value for key, value in source.items() if key != "path"}
for check in results["results"].values():
    check["http"] = [{key: value for key, value in request.items() if value is not None}
                     for request in check["http"]]
    if any(request["path"].endswith("/File") for request in check["http"]):
        raise RuntimeError("A forbidden File fallback was observed")
    if any(request["method"] != "GET" and request["path"].startswith("/Sessions/")
           for request in check["http"]):
        raise RuntimeError("Playback reporting is outside this acceptance suite")
results["jellyfinArchive"] = {key: value for key, value in pins["jellyfin"].items()
                            if key in ["binaryArchiveUrl", "binaryArchiveHash", "binaryDllSha256"]}
results["nixpkgsCommit"] = pins["nixpkgs"]["commit"]
results["enhancedInstalled"] = any((runtime / "data/plugins").glob("**/Jellyfin.Plugin.JellyfinEnhanced.dll"))
if results["enhancedInstalled"]:
    raise RuntimeError("This acceptance fixture must run without Enhanced")
results["syntheticSources"] = synthetic_sources
results["platformSecureStorageExercised"] = False
results["androidDeviceExercised"] = False
results["playbackWritesObserved"] = 0
serialized = json.dumps(results, indent=2) + "\n"
secrets = list(passwords.values()) + [account["token"] for account in accounts.values()]
if any(secret in serialized for secret in secrets):
    raise RuntimeError("Refusing to publish fixture credentials")
output = repository / "tool/acceptance/evidence/app-http.json"
output.parent.mkdir(exist_ok=True)
output.write_text(serialized)
print("Published nine passing app checks without credentials or host media paths")
