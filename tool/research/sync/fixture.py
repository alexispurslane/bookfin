import ipaddress
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[3] / ".cache" / "sync" / "runtime"
ORIGIN = "http://127.0.0.1:7364"


def validate_origin(origin):
    parsed = urllib.parse.urlsplit(origin)
    if (parsed.scheme != "http" or not parsed.hostname or not parsed.port
            or parsed.username or parsed.password or parsed.path
            or parsed.query or parsed.fragment
            or not ipaddress.ip_address(parsed.hostname).is_loopback):
        raise ValueError("Only a bare, literal loopback HTTP origin is allowed")
    return origin


def require_download(policy):
    if policy.get("EnableContentDownloading") is not True:
        raise PermissionError("An explicit download permission is required; never fall back to File")


def is_ready(public_info):
    return (isinstance(public_info, dict) and public_info.get("Version") == "12.4.0"
            and bool(public_info.get("Id")))


def private_json(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as output:
        os.fchmod(output.fileno(), 0o600)
        json.dump(value, output, indent=2)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


class Api:
    def __init__(self, token=None, origin=ORIGIN, timeout=30):
        self.origin = validate_origin(origin)
        self.token = token
        self.timeout = timeout
        self.opener = urllib.request.OpenerDirector()
        for handler in [urllib.request.HTTPHandler(), urllib.request.HTTPDefaultErrorHandler(),
                        urllib.request.HTTPErrorProcessor(), NoRedirect()]:
            self.opener.add_handler(handler)

    def request(self, method, path, value=None, headers=None):
        if not path.startswith("/") or path.startswith("//") or "://" in path:
            raise ValueError("Only relative API paths are allowed")
        request_headers = {
            "Authorization": 'MediaBrowser Client="Bookfin disposable research", Device="Synthetic", DeviceId="ta-qobz", Version="1"',
        }
        if self.token:
            request_headers["Authorization"] += f', Token="{self.token}"'
        request_headers.update(headers or {})
        body = None
        if value is not None:
            body = json.dumps(value).encode()
            request_headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.origin + path, data=body, method=method, headers=request_headers)
        try:
            response = self.opener.open(request, timeout=self.timeout)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            content = response.read(2 * 1024 * 1024 + 1)
            if len(content) > 2 * 1024 * 1024:
                raise ValueError("Response exceeds the bounded research buffer")
            return response.status, dict(response.headers), content

    def json(self, method, path, value=None, expected=(200, 204)):
        status, headers, body = self.request(method, path, value)
        if status not in expected:
            raise RuntimeError(f"{method} {path.split('?')[0]} returned HTTP {status}")
        return json.loads(body) if body else None

    def download(self, item_id, policy):
        require_download(policy)
        return self.request("GET", f"/Items/{item_id}/Download", headers={"Range": "bytes=0-31"})


def prepare():
    os.umask(0o077)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    marker = ROOT / "fixture.json"
    if marker.exists():
        return
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 7364))
    for directory in ["data", "config", "cache", "logs", "media/public", "media/private"]:
        (ROOT / directory).mkdir(parents=True, exist_ok=True)
    (ROOT / "config" / "network.xml").write_text('''<?xml version="1.0"?>
<NetworkConfiguration>
  <InternalHttpPort>7364</InternalHttpPort><PublicHttpPort>7364</PublicHttpPort>
  <EnableHttps>false</EnableHttps><EnableIPv4>true</EnableIPv4><EnableIPv6>false</EnableIPv6>
  <EnableRemoteAccess>false</EnableRemoteAccess><EnableUPnP>false</EnableUPnP><AutoDiscovery>false</AutoDiscovery>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
</NetworkConfiguration>
''')
    plugin = ROOT / "data/plugins/Jellyfin Enhanced_12.14.0.0"
    plugin.mkdir(parents=True)
    shutil.copy2(Path(os.environ["BOOKFIN_SYNC_ENHANCED"]) / "Jellyfin.Plugin.JellyfinEnhanced.dll", plugin)
    private_json(plugin / "meta.json", {
        "name": "Jellyfin Enhanced", "guid": "f69e946a-4b3c-4e9a-8f0a-8d7c1b2c4d9b",
        "version": "12.14.0.0", "targetAbi": "12.0.0.0", "status": "Active", "owner": "n00bcodr",
        "description": "Pinned official release archive; disposable research only",
    })
    private_json(marker, {"origin": ORIGIN, "purpose": "ta-qobz synthetic only"})


def serve():
    prepare()
    executable = str(Path(os.environ["BOOKFIN_SYNC_SERVER"]) / "jellyfin")
    os.execv(executable, [executable, "--datadir", str(ROOT / "data"),
                         "--configdir", str(ROOT / "config"), "--cachedir", str(ROOT / "cache"),
                         "--logdir", str(ROOT / "logs"), "--nowebclient",
                         "--ffmpeg", shutil.which("ffmpeg")])


def login(name, password):
    return Api().json("POST", "/Users/AuthenticateByName", {"Username": name, "Pw": password})


def wait_ready():
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        try:
            if is_ready(Api(timeout=2).json("GET", "/System/Info/Public")):
                print("Disposable Jellyfin 12.4.0 is ready")
                return
        except (OSError, RuntimeError, json.JSONDecodeError):
            pass
        time.sleep(0.5)
    raise RuntimeError("Disposable Jellyfin did not become ready within 90 seconds")


def seed_media():
    for folder, tracks in [("public/Work/Recording A", [("z-first", 1, 1), ("a-second", 2, 1), ("m-third", 1, 2)]),
                           ("public/Work/Recording B", [("other-narrator", 1, 1)]),
                           ("private/Hidden", [("secret-synthetic", 1, 1)])]:
        destination = ROOT / "media" / folder
        destination.mkdir(parents=True, exist_ok=True)
        for name, track, disc in tracks:
            output = destination / f"{name}.m4b"
            if not output.exists():
                subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-threads", "1", "-f", "lavfi",
                                "-i", "sine=frequency=440:duration=180", "-c:a", "aac", "-b:a", "16k",
                                "-metadata", f"title={name}", "-metadata", "album=Synthetic Work",
                                "-metadata", "artist=Research Author", "-metadata", f"track={track}",
                                "-metadata", f"disc={disc}", str(output)], check=True)
    first = ROOT / "media/public/Work/Recording A/z-first.m4b"
    chapters = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_chapters", "-of", "json", str(first)]))
    if not chapters.get("chapters"):
        metadata = ROOT / "chapters.ffmeta"
        metadata.write_text(";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=90000\ntitle=Beginning\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=90000\nEND=180000\ntitle=Ending\n")
        replacement = first.with_name("chaptered.m4b")
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-i", str(first), "-f", "ffmetadata", "-i", str(metadata),
                        "-map", "0", "-map_metadata", "0", "-map_chapters", "1", "-c", "copy", str(replacement)], check=True)
        replacement.replace(first)
    import zipfile
    ebook = ROOT / "media/public/Work/Text Edition"
    ebook.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ebook / "Synthetic Work.epub", "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        archive.writestr("content.opf", '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Synthetic Work</dc:title><dc:creator>Research Author</dc:creator><dc:identifier id="id">urn:bookfin:synthetic</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>')
        archive.writestr("chapter.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Synthetic only</h1><p>Disposable research.</p></body></html>')


def seed():
    state_file = ROOT / "accounts.json"
    if state_file.exists():
        raise RuntimeError("Already seeded; preserve the existing synthetic accounts")
    seed_media()
    password_file = ROOT / "passwords.json"
    if password_file.exists():
        passwords = json.loads(password_file.read_text())
    else:
        passwords = {name: secrets.token_urlsafe(24) for name in ["research-admin", "research-alice", "research-bob"]}
        private_json(password_file, passwords)
    if not Api().json("GET", "/System/Info/Public")["StartupWizardCompleted"]:
        Api().json("GET", "/Startup/FirstUser")
        Api().json("POST", "/Startup/User", {"Name": "research-admin", "Password": passwords["research-admin"]})
        Api().json("POST", "/Startup/Complete")
    admin_auth = login("research-admin", passwords["research-admin"])
    admin = Api(admin_auth["AccessToken"])
    accounts = {"admin": {"id": admin_auth["User"]["Id"], "token": admin_auth["AccessToken"]}}
    for name in ["alice", "bob"]:
        user = admin.json("POST", "/Users/New", {"Name": "research-" + name, "Password": passwords["research-" + name]})
        policy = user["Policy"]
        policy.update(IsAdministrator=False, EnableAllFolders=False, EnabledFolders=[],
                      EnableContentDownloading=True, EnableMediaPlayback=True,
                      EnableContentDeletion=False, EnableAllDevices=True)
        admin.json("POST", f'/Users/{user["Id"]}/Policy', policy)
        auth = login("research-" + name, passwords["research-" + name])
        accounts[name] = {"id": user["Id"], "token": auth["AccessToken"]}
    for label in ["public", "private"]:
        query = urllib.parse.urlencode({"name": "Synthetic " + label, "collectionType": "books", "refreshLibrary": "false"})
        admin.json("POST", "/Library/VirtualFolders?" + query, {"LibraryOptions": {
            "PathInfos": [{"Path": str(ROOT / "media" / label)}], "EnableRealtimeMonitor": False,
            "EnableInternetProviders": False, "EnableChapterImageExtraction": False,
            "EnableEmbeddedTitles": True, "AutomaticRefreshIntervalDays": 0,
        }})
    libraries = admin.json("GET", "/Library/VirtualFolders")
    for name in ["alice", "bob"]:
        account = accounts[name]
        policy = admin.json("GET", f'/Users/{account["id"]}')["Policy"]
        policy["EnabledFolders"] = [library["ItemId"] for library in libraries
                                    if library["Name"] == "Synthetic public" or name == "alice"]
        admin.json("POST", f'/Users/{account["id"]}/Policy', policy)
    private_json(state_file, accounts)
    admin.json("POST", "/Library/Refresh")
    public = Api().json("GET", "/System/Info/Public")
    private_json(ROOT / "fixture.json", {"origin": ORIGIN, "purpose": "ta-qobz synthetic only", "serverId": public["Id"]})
    print("Seeded two ordinary users, two books libraries, five synthetic audio files and one EPUB")


def stop():
    marker = json.loads((ROOT / "fixture.json").read_text())
    public = Api().json("GET", "/System/Info/Public")
    if public["Id"] != marker.get("serverId"):
        raise RuntimeError("Refusing to shut down an unrecognized server")
    accounts = json.loads((ROOT / "accounts.json").read_text())
    Api(accounts["admin"]["token"]).json("POST", "/System/Shutdown")
    print("Requested shutdown of this disposable server only")


if __name__ == "__main__":
    if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
        raise SystemExit("Run through nix develop ./tool/research/sync")
    commands = {"prepare": prepare, "serve": serve, "wait": wait_ready, "seed": seed, "seed-media": seed_media, "stop": stop}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        raise SystemExit("Use prepare, serve, wait, seed, seed-media, or stop")
    commands[sys.argv[1]]()
