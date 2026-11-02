import json
from pathlib import Path
import sqlite3
import sys


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "sync"))
from finite_journal import validate_action


class Outbox:
    def __init__(self, path, server_id, user_id, device):
        self.scope = (server_id, user_id, device)
        self.database = sqlite3.connect(path, timeout=10)
        self.database.execute("PRAGMA synchronous=FULL")
        try:
            with self.database:
                self.database.execute("BEGIN IMMEDIATE")
                self.database.execute("""CREATE TABLE IF NOT EXISTS scope(
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    server TEXT NOT NULL, user TEXT NOT NULL, device TEXT NOT NULL)""")
                self.database.execute("""CREATE TABLE IF NOT EXISTS actions(
                    identity TEXT PRIMARY KEY, payload TEXT NOT NULL, acknowledged INTEGER NOT NULL DEFAULT 0
                    CHECK(acknowledged IN (0,1)))""")
                existing = self.database.execute("SELECT server, user, device FROM scope").fetchall()
                if not existing:
                    self.database.execute("INSERT INTO scope VALUES (1, ?, ?, ?)", self.scope)
                elif existing != [self.scope]:
                    raise PermissionError("Pending actions belong to another server, user, or installation")
        except Exception:
            self.database.close()
            raise

    def enqueue(self, action):
        validate_action(action)
        if action["device"] != self.scope[2]:
            raise ValueError("The installation must own its pending actions")
        identity = f'action.{action["device"]}.{action["sequence"]}'
        payload = json.dumps(action, sort_keys=True, separators=(",", ":"))
        with self.database:
            self.database.execute("BEGIN IMMEDIATE")
            existing = self.database.execute("SELECT payload FROM actions WHERE identity=?", (identity,)).fetchone()
            if existing is not None and existing[0] != payload:
                raise ValueError("An immutable action identity has conflicting payloads")
            self.database.execute("INSERT OR IGNORE INTO actions(identity, payload) VALUES (?, ?)", (identity, payload))

    def pending(self):
        return [json.loads(row[0]) for row in self.database.execute(
            "SELECT payload FROM actions WHERE acknowledged=0 ORDER BY identity")]

    def flush(self, api):
        public = api.json("GET", "/System/Info/Public")
        user = api.json("GET", "/Users/Me")
        if (public["Id"], user["Id"]) != self.scope[:2]:
            raise PermissionError("Refusing to upload pending actions through another account")
        for identity, payload in self.database.execute(
                "SELECT identity, payload FROM actions WHERE acknowledged=0 ORDER BY identity").fetchall():
            status, _, body = api.request("PUT", "/BookfinStorage/v1/objects/" + identity, {"Payload": payload})
            if status not in (200, 201):
                raise RuntimeError(f"Pending action remains locally retained after HTTP {status}")
            stored = json.loads(body)
            if stored["Id"] != identity or stored["Payload"] != payload or stored["Deleted"]:
                raise RuntimeError("Unverified acknowledgment; pending action remains locally retained")
            with self.database:
                self.database.execute("UPDATE actions SET acknowledged=1 WHERE identity=? AND payload=?", (identity, payload))

    def close(self):
        self.database.close()

    def check_invariants(self):
        if self.database.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise AssertionError("Outbox integrity failed")
        if self.database.execute("SELECT server, user, device FROM scope").fetchall() != [self.scope]:
            raise AssertionError("Outbox ownership changed")
        for identity, payload, acknowledged in self.database.execute("SELECT identity, payload, acknowledged FROM actions"):
            action = json.loads(payload)
            validate_action(action)
            if (action["device"] != self.scope[2] or identity != f'action.{action["device"]}.{action["sequence"]}'
                    or acknowledged not in (0, 1)):
                raise AssertionError("Outbox action identity or acknowledgment is invalid")
