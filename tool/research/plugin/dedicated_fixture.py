import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time


SYNC = Path(__file__).resolve().parents[1] / "sync"
sys.path.insert(0, str(SYNC))
from fixture import Api, private_json


ORIGIN = "http://127.0.0.1:7464"
CACHE = Path(__file__).resolve().parents[3] / ".cache/plugin"


class Server:
    def __init__(self):
        if os.environ.get("BOOKFIN_SYNC_SHELL") != "1":
            raise RuntimeError("Run through nix develop ./tool/research/sync")
        os.umask(0o077)
        CACHE.mkdir(parents=True, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="run-", dir=CACHE))
        self.process = None
        self.log = None
        self.server_id = None
        self.accounts = {}
        self.starts = []
        self.stops = []
        for port in (7464, 7465):
            with socket.socket() as listener:
                listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                listener.bind(("127.0.0.1", port))
        for directory in ("data", "config", "cache", "logs"):
            (self.root / directory).mkdir()
        (self.root / "config/network.xml").write_text('''<NetworkConfiguration>
  <InternalHttpPort>7464</InternalHttpPort><PublicHttpPort>7464</PublicHttpPort>
  <InternalHttpsPort>7465</InternalHttpsPort><PublicHttpsPort>7465</PublicHttpsPort>
  <EnableHttps>false</EnableHttps><EnableIPv4>true</EnableIPv4><EnableIPv6>false</EnableIPv6>
  <EnableRemoteAccess>false</EnableRemoteAccess><EnableUPnP>false</EnableUPnP><AutoDiscovery>false</AutoDiscovery>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
</NetworkConfiguration>''')
        plugin = self.root / "data/plugins/Bookfin Storage Research_0.1.0.0"
        plugin.mkdir(parents=True)
        shutil.copy2(CACHE / "build/Bookfin.Storage.dll", plugin)
        private_json(plugin / "meta.json", {
            "name": "Bookfin Storage Research", "guid": "55fb5a92-7fbd-411c-9838-6ee4c88d168b",
            "version": "0.1.0.0", "targetAbi": "12.0.0.0", "status": "Active",
            "description": "Disposable dedicated-storage proof", "owner": "Bookfin research",
        })
        private_json(self.root / "fixture.json", {"origin": ORIGIN, "purpose": "boo-dez0 synthetic only"})

    def start(self):
        executable = str(Path(os.environ["BOOKFIN_SYNC_SERVER"]) / "jellyfin")
        self.log = (self.root / "console.log").open("ab")
        self.process = subprocess.Popen([
            executable, "--datadir", str(self.root / "data"),
            "--configdir", str(self.root / "config"), "--cachedir", str(self.root / "cache"),
            "--logdir", str(self.root / "logs"), "--nowebclient", "--ffmpeg", shutil.which("ffmpeg"),
        ], stdout=self.log, stderr=subprocess.STDOUT,
            env={**os.environ, "BOOKFIN_STORAGE_CHECK_INVARIANTS": "1"})
        self.starts.append({"after": self.stops[-1]["kind"] if self.stops else "initial"})
        private_json(self.root / "process.json", {"pid": self.process.pid})
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(f"Own fixture exited; inspect {self.root}/console.log privately")
            try:
                public = Api(origin=ORIGIN, timeout=2).json("GET", "/System/Info/Public")
                if public.get("Version") == "12.4.0" and public.get("Id"):
                    if self.server_id is not None and self.server_id != public["Id"]:
                        raise RuntimeError("Fixture identity changed")
                    self.server_id = public["Id"]
                    return
            except (OSError, RuntimeError, json.JSONDecodeError):
                pass
            time.sleep(0.2)
        raise RuntimeError("Own fixture did not become ready within 90 seconds")

    def stop(self, force=False):
        if self.process is not None and self.process.poll() is None:
            if force:
                self.process.kill()
            else:
                self.process.terminate()
            try:
                self.process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=10)
            self.stops.append({"kind": "kill" if force else "terminate", "exitCode": self.process.returncode})
        if self.log is not None:
            self.log.close()

    def seed(self):
        passwords = {name: secrets.token_urlsafe(24) for name in ("admin", "alice", "bob")}
        public = Api(origin=ORIGIN)
        public.json("GET", "/Startup/FirstUser")
        public.json("POST", "/Startup/User", {"Name": "research-admin", "Password": passwords["admin"]})
        public.json("POST", "/Startup/Complete")
        for name in ("admin", "alice", "bob"):
            if name != "admin":
                user = self.api("admin").json("POST", "/Users/New", {
                    "Name": "research-" + name, "Password": passwords[name]})
                if user["Policy"]["IsAdministrator"]:
                    raise RuntimeError("Fixture account must be an ordinary user")
            auth = public.json("POST", "/Users/AuthenticateByName", {
                "Username": "research-" + name, "Pw": passwords[name]})
            self.accounts[name] = {"id": auth["User"]["Id"], "token": auth["AccessToken"]}
        private_json(self.root / "accounts.json", self.accounts)
        private_json(self.root / "passwords.json", passwords)

    def api(self, name):
        return Api(self.accounts[name]["token"], origin=ORIGIN)
