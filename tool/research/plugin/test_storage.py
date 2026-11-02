from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import socket
import sys
import time
import unittest


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from dedicated_fixture import Api, ORIGIN, Server
from finite_journal import Journal
from outbox import Outbox


BASE = "/BookfinStorage/v1/objects"


class DedicatedStorage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Server()
        cls.addClassCleanup(cls.server.stop)
        cls.server.start()
        cls.server.seed()

    def put(self, identity, payload, name="alice"):
        return self.server.api(name).request("PUT", f"{BASE}/{identity}", {"Payload": payload})[0]

    def discover(self, name="alice", after=0, limit=4):
        objects = []
        for _ in range(128):
            page = self.server.api(name).json("GET", f"{BASE}?after={after}&limit={limit}")
            objects.extend(page["Objects"])
            if not page["HasMore"]:
                return objects, page["Cursor"]
            self.assertGreater(page["Cursor"], after)
            after = page["Cursor"]
        self.fail("The bounded discovery budget was exhausted; no partial inventory is accepted")

    def test_01_independent_concurrent_writes_are_all_discoverable(self):
        def publish(number):
            return self.put(f"concurrent-{number:03}", f"history-{number:03}")
        with ThreadPoolExecutor(max_workers=8) as writers:
            self.assertEqual(list(writers.map(publish, range(80))), [201] * 80)
        objects, cursor = self.discover(limit=3)
        captured = {item["Id"]: item["Payload"] for item in objects if item["Id"].startswith("concurrent-")}
        self.assertEqual(captured, {f"concurrent-{number:03}": f"history-{number:03}" for number in range(80)})
        self.assertGreaterEqual(cursor, 80)

    def test_02_retries_do_not_duplicate_or_overwrite_an_identity(self):
        self.assertEqual(self.put("retry", "original"), 201)
        before = self.discover()[1]
        with ThreadPoolExecutor(max_workers=8) as writers:
            statuses = list(writers.map(lambda _: self.put("retry", "original"), range(16)))
        self.assertEqual(statuses, [200] * 16)
        self.assertEqual(self.put("retry", "changed"), 409)
        self.assertEqual(self.discover()[1], before)
        stored = self.server.api("alice").json("GET", f"{BASE}/retry")
        self.assertEqual(stored["Payload"], "original")

    def test_03_normal_accounts_cannot_read_write_or_delete_each_others_objects(self):
        self.assertEqual(self.put("private", "alice-only"), 201)
        bob = self.server.api("bob")
        alice_id = self.server.accounts["alice"]["id"]
        self.assertEqual(bob.request("GET", f"{BASE}/private?userId={alice_id}")[0], 404)
        self.assertEqual(self.discover("bob")[0], [])
        self.assertEqual(self.put("private", "bob-only", "bob"), 201)
        self.assertEqual(bob.request("DELETE", f"{BASE}/private?userId={alice_id}")[0], 204)
        self.assertEqual(self.server.api("alice").json("GET", f"{BASE}/private")["Payload"], "alice-only")
        for method, suffix, value in (("GET", "", None), ("GET", "/private", None),
                                       ("PUT", "/private", {"Payload": "attacker"}), ("DELETE", "/private", None)):
            self.assertEqual(Api(origin=ORIGIN).request(method, BASE + suffix, value)[0], 401)

    def test_04_explicit_delete_is_discoverable_and_blocks_delayed_uploads(self):
        self.assertEqual(self.put("deleted", "erase-this"), 201)
        cursor = self.discover()[1]
        alice = self.server.api("alice")
        self.assertEqual(alice.request("DELETE", f"{BASE}/deleted")[0], 204)
        removed, deletion_cursor = self.discover(after=cursor)
        self.assertEqual([(item["Id"], item["Payload"], item["Deleted"]) for item in removed],
                         [("deleted", None, True)])
        self.assertEqual(alice.request("GET", f"{BASE}/deleted")[0], 410)
        self.assertEqual(self.put("deleted", "erase-this"), 410)
        self.assertEqual(alice.request("DELETE", f"{BASE}/deleted")[0], 204)
        self.assertEqual(self.discover()[1], deletion_cursor)
        self.assertEqual(alice.request("DELETE", f"{BASE}/delete-before-upload")[0], 204)
        self.assertEqual(self.put("delete-before-upload", "delayed"), 410)

    def test_05_known_request_limits_fail_without_changing_history(self):
        self.assertEqual(self.put("large", "x" * 65536), 201)
        before = self.discover()[1]
        self.assertEqual(self.put("too-large", "é" * 32769), 413)
        for query in ("after=-1", "limit=0", "limit=5", "after=not-a-number"):
            self.assertEqual(self.server.api("alice").request("GET", BASE + "?" + query)[0], 400)
        self.assertEqual(self.put("invalid!", "bad"), 400)
        self.assertEqual(self.put("empty", ""), 400)
        self.assertEqual(self.discover()[1], before)

    def test_06_clean_and_forced_restarts_preserve_acknowledged_objects_and_deletions(self):
        self.assertEqual(self.put("restart-live", "retained"), 201)
        self.assertEqual(self.server.api("alice").request("DELETE", f"{BASE}/restart-deleted")[0], 204)
        before = self.discover()
        for force in (False, True):
            self.server.stop(force=force)
            self.server.start()
            self.assertEqual(self.discover(), before)
            self.assertEqual(self.put("restart-deleted", "late"), 410)

    def journal(self, prefix):
        objects = self.discover()[0]
        actions = [json.loads(item["Payload"]) for item in objects
                   if item["Id"].startswith(prefix) and not item["Deleted"]]
        journal = Journal()
        journal.receive(list(reversed(actions)))
        journal.check_invariants()
        return journal

    def test_07_bookfin_retains_concurrent_versions_despite_clock_skew(self):
        first = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
                 "record": "bookmark", "kind": "put", "value": {"position_ms": 12000, "clock": "2099-01-01"}}
        second = {**first, "device": "device-b", "value": {"position_ms": 9000, "clock": "1970-01-01"}}
        with ThreadPoolExecutor(max_workers=2) as writers:
            statuses = list(writers.map(lambda action: self.put(
                "journal-" + action["device"] + "-1", json.dumps(action)), (first, second)))
        self.assertEqual(statuses, [201, 201])
        self.assertCountEqual(self.journal("journal-").values("bookmark"), [first["value"], second["value"]])
        deletion = {**first, "sequence": 2, "context": {"device-a": 1, "device-b": 1},
                    "kind": "delete", "value": None}
        self.assertEqual(self.put("journal-device-a-2", json.dumps(deletion)), 201)
        self.assertEqual(self.put("journal-device-a-1", json.dumps(first)), 200)
        self.assertEqual(self.journal("journal-").values("bookmark"), [])
        self.assertEqual(self.journal("journal-").coverage, {"device-a": 2, "device-b": 1})

    def test_08_missing_earlier_actions_remain_waiting_across_restart(self):
        first = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
                 "record": "history", "kind": "put", "value": "first"}
        later = {**first, "sequence": 2, "context": {"device-a": 1, "device-b": 0}, "value": "second"}
        self.assertEqual(self.put("gap-2", json.dumps(later)), 201)
        waiting = self.journal("gap-")
        self.assertEqual(waiting.coverage, {"device-a": 0, "device-b": 0})
        self.assertEqual(list(waiting.pending.values()), [later])
        self.server.stop()
        self.server.start()
        self.assertEqual(list(self.journal("gap-").pending.values()), [later])
        self.assertEqual(self.put("gap-1", json.dumps(first)), 201)
        self.assertEqual(self.journal("gap-").coverage, {"device-a": 2, "device-b": 0})
        self.assertEqual(self.journal("gap-").values("history"), ["second"])

    def test_09_pending_actions_survive_lost_acknowledgments_and_rejected_retries(self):
        path = self.server.root / "outbox.sqlite"
        scope = (self.server.server_id, self.server.accounts["alice"]["id"], "device-a")
        box = Outbox(path, *scope)
        self.addCleanup(box.close)
        first = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
                 "record": "offline-bookmark", "kind": "put", "value": "retained"}
        box.enqueue(first)
        alice = self.server.api("alice")

        class LostAcknowledgment(Api):
            def request(self, method, path, value=None, headers=None):
                if method == "PUT":
                    payload = json.dumps(value).encode()
                    authorization = ('MediaBrowser Client="Bookfin lost-ack research", Device="Synthetic", '
                                     f'DeviceId="boo-dez0-lost-ack", Version="1", Token="{self.token}"')
                    head = (f"PUT {path} HTTP/1.1\r\nHost: 127.0.0.1:7464\r\n"
                            f"Authorization: {authorization}\r\nContent-Type: application/json\r\n"
                            f"Content-Length: {len(payload)}\r\nConnection: close\r\n\r\n")
                    with socket.create_connection(("127.0.0.1", 7464), timeout=5) as connection:
                        connection.sendall(head.encode() + payload)
                        deadline = time.monotonic() + 5
                        while time.monotonic() < deadline:
                            status, _, body = alice.request("GET", path)
                            if status == 200 and json.loads(body)["Payload"] == value["Payload"]:
                                break
                            time.sleep(0.02)
                        else:
                            raise AssertionError("An independent connection did not witness the committed action")
                    raise TimeoutError("Synthetic lost acknowledgment after the server committed")
                return super().request(method, path, value, headers)

        with self.assertRaises(TimeoutError):
            box.flush(LostAcknowledgment(alice.token, origin=ORIGIN))
        self.assertEqual(box.pending(), [first])
        box.close()
        box = Outbox(path, *scope)
        self.addCleanup(box.close)
        self.assertEqual(box.pending(), [first])
        with self.assertRaises(PermissionError):
            box.flush(self.server.api("bob"))
        box.flush(alice)
        self.assertEqual(box.pending(), [])
        stored = [item for item in self.discover()[0] if item["Id"] == "action.device-a.1"]
        self.assertEqual(len(stored), 1)
        self.assertEqual(json.loads(stored[0]["Payload"]), first)
        second = {**first, "sequence": 2, "context": {"device-a": 1, "device-b": 0}, "value": "pending"}
        box.enqueue(second)
        self.assertEqual(alice.request("DELETE", BASE + "/action.device-a.2")[0], 204)
        with self.assertRaisesRegex(RuntimeError, "410"):
            box.flush(alice)
        self.assertEqual(box.pending(), [second])
        box.check_invariants()

    def test_10_uploads_racing_with_deletion_cannot_restore_the_deleted_identity(self):
        def race(number):
            if number % 2:
                return self.server.api("alice").request("DELETE", BASE + "/race-deleted")[0]
            return self.put("race-deleted", "racing")
        with ThreadPoolExecutor(max_workers=8) as writers:
            statuses = list(writers.map(race, range(32)))
        self.assertTrue(all(status in (200, 201, 204, 410) for status in statuses))
        self.assertEqual(self.server.api("alice").request("GET", BASE + "/race-deleted")[0], 410)
        self.assertEqual(self.put("race-deleted", "delayed"), 410)

    def test_11_dedicated_objects_are_not_ordinary_playlist_items(self):
        self.assertEqual(self.put("not-a-playlist", "private-history"), 201)
        playlists = self.server.api("alice").json("GET", "/Items?IncludeItemTypes=Playlist&Recursive=true")
        self.assertEqual(playlists["Items"], [])

    def test_12_a_cursor_discovers_changes_made_between_pages(self):
        bob = self.server.api("bob")
        cursor = self.discover("bob")[1]
        for identity in ("page-a", "page-b", "page-c"):
            self.assertEqual(self.put(identity, identity, "bob"), 201)
        first = bob.json("GET", f"{BASE}?after={cursor}&limit=1")
        self.assertEqual([item["Id"] for item in first["Objects"]], ["page-a"])
        self.assertEqual(bob.request("DELETE", BASE + "/page-b")[0], 204)
        self.assertEqual(bob.request("DELETE", BASE + "/page-a")[0], 204)
        self.assertEqual(self.put("page-d", "page-d", "bob"), 201)
        rest, cursor = self.discover("bob", after=first["Cursor"], limit=1)
        latest = {item["Id"]: item["Payload"] for item in first["Objects"] + rest}
        self.assertEqual(latest, {"page-a": None, "page-b": None, "page-c": "page-c", "page-d": "page-d"})
        self.assertEqual(self.discover("bob", after=cursor)[0], [])

    def test_13_history_events_remain_independent_until_one_is_explicitly_deleted(self):
        first = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
                 "record": "history-event-one", "kind": "put", "value": {"clock": "1970-01-01", "position_ms": 8000}}
        second = {**first, "sequence": 2, "context": {"device-a": 1, "device-b": 0},
                  "record": "history-event-two", "value": {"clock": "1970-01-02", "position_ms": 5000}}
        for action in (first, second):
            self.assertEqual(self.put(f'history-{action["sequence"]}', json.dumps(action)), 201)
        history = self.journal("history-")
        self.assertEqual(history.values("history-event-one"), [first["value"]])
        self.assertEqual(history.values("history-event-two"), [second["value"]])
        deletion = {**first, "sequence": 3, "context": {"device-a": 2, "device-b": 0}, "kind": "delete", "value": None}
        self.assertEqual(self.put("history-3", json.dumps(deletion)), 201)
        self.assertEqual(self.journal("history-").values("history-event-one"), [])
        self.assertEqual(self.journal("history-").values("history-event-two"), [second["value"]])

    def test_14_a_genuinely_concurrent_edit_remains_a_conflict_with_deletion(self):
        create = {"device": "device-a", "sequence": 1, "context": {"device-a": 0, "device-b": 0},
                  "record": "bookmark", "kind": "put", "value": "original"}
        deletion = {**create, "sequence": 2, "context": {"device-a": 1, "device-b": 0}, "kind": "delete", "value": None}
        edit = {**create, "device": "device-b", "context": {"device-a": 1, "device-b": 0}, "value": "offline edit"}
        for identity, action in (("birth", create), ("delete", deletion), ("offline-edit", edit)):
            self.assertEqual(self.put("conflict-" + identity, json.dumps(action)), 201)
        conflict = self.journal("conflict-")
        versions = list(conflict.records["bookmark"].values())
        self.assertCountEqual(versions, [deletion, edit])

    def test_15_plugin_remains_active_after_its_restart_exercises(self):
        plugins = self.server.api("admin").json("GET", "/Plugins")
        storage = [plugin for plugin in plugins if plugin["Id"].replace("-", "") == "55fb5a927fbd411c98386ee4c88d168b"]
        self.assertEqual(len(storage), 1)
        self.assertEqual(storage[0]["Status"], "Active")

    def test_16_opaque_payloads_preserve_leading_null_characters(self):
        self.assertEqual(self.put("null-character", "\x00opaque"), 201)
        stored = self.server.api("alice").json("GET", BASE + "/null-character")
        self.assertEqual(stored["Payload"], "\x00opaque")


if __name__ == "__main__":
    unittest.main(verbosity=2)
