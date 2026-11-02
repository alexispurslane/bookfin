from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import unittest

from fixture import Api
from playlist_protocol import discover_operations, measure_privacy


@contextmanager
def payload_server(owner_status=200, owner_name="private synthetic note", other_status=404,
                   other_body=b"not found"):
    class PayloadRoute(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/Items/synthetic-playlist":
                self.send_response(405)
                self.end_headers()
                return
            owner = 'Token="alice"' in self.headers.get("Authorization", "")
            self.send_response(owner_status if owner else other_status)
            self.end_headers()
            self.wfile.write(json.dumps({"Name": owner_name}).encode() if owner else other_body)

        def log_message(self, *arguments):
            pass

    with ThreadingHTTPServer(("127.0.0.1", 0), PayloadRoute) as server:
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        origin = f"http://127.0.0.1:{server.server_port}"
        try:
            yield Api("alice", origin, timeout=2), Api("bob", origin, timeout=2)
        finally:
            server.shutdown()
            worker.join(timeout=5)


class PrivacyEvidenceTests(unittest.TestCase):
    def measure(self, clients):
        return measure_privacy(*clients, "synthetic-playlist", "private synthetic note")

    def test_privacy_evidence_reads_the_same_payload_route_for_both_users(self):
        with payload_server() as clients:
            measured = self.measure(clients)
        self.assertEqual(measured, {
            "route": "/Items/{samePlaylistId}", "ownerStatus": 200,
            "ownerExactPayload": True, "otherUserStatus": 404,
            "otherUserPayloadExposed": False, "otherUserResponseBytes": 9,
            "sameObjectAndRoute": True,
        })

    def test_two_denied_reads_do_not_establish_payload_confidentiality(self):
        with payload_server(owner_status=404) as clients:
            with self.assertRaises(AssertionError):
                self.measure(clients)


    def test_an_owner_read_of_the_wrong_payload_does_not_establish_confidentiality(self):
        with payload_server(owner_name="wrong note") as clients:
            with self.assertRaises(AssertionError):
                self.measure(clients)

    def test_a_successful_other_user_read_is_not_accepted_as_denial(self):
        with payload_server(other_status=200) as clients:
            with self.assertRaises(AssertionError):
                self.measure(clients)

    def test_a_denied_response_that_contains_the_payload_is_not_confidential(self):
        with payload_server(other_body=b"private synthetic note") as clients:
            with self.assertRaises(AssertionError):
                self.measure(clients)

    def test_a_denied_json_response_cannot_hide_an_escaped_payload(self):
        payload = '{"note":"synthetic private note"}'
        with payload_server(owner_name=payload, other_body=json.dumps({"Name": payload}).encode()) as clients:
            with self.assertRaises(AssertionError):
                measure_privacy(*clients, "synthetic-playlist", payload)

    def test_denied_response_rejects_payload_in_any_decoded_string(self):
        payload = '{"note":"synthetic private note"}'
        for document in [{"detail": payload}, {"errors": [{"detail": "prefix " + payload + " suffix"}]}, [payload]]:
            with self.subTest(document=document):
                with payload_server(owner_name=payload, other_body=json.dumps(document).encode()) as clients:
                    with self.assertRaises(AssertionError):
                        measure_privacy(*clients, "synthetic-playlist", payload)


class JournalDiscoveryTests(unittest.TestCase):
    def test_a_lost_ack_retry_is_one_logical_operation(self):
        payload = {"namespace": "synthetic", "operationId": "alice:1", "kind": "put"}
        items = [{"Id": "first", "Name": json.dumps(payload)},
                 {"Id": "retry", "Name": json.dumps(payload)}]
        self.assertEqual(discover_operations(items, "synthetic"), {"alice:1": payload})

    def test_independent_offline_edits_both_survive_discovery(self):
        first = {"namespace": "synthetic", "operationId": "alice:1", "kind": "put"}
        second = {"namespace": "synthetic", "operationId": "bob:1", "kind": "put"}
        items = [{"Id": "first", "Name": json.dumps(first)},
                 {"Id": "second", "Name": json.dumps(second)}]
        self.assertEqual(discover_operations(items, "synthetic"), {"alice:1": first, "bob:1": second})

    def test_discovery_excludes_pending_and_unrelated_playlists(self):
        items = [{"Name": "synthetic-pending"}, {"Name": "[]"},
                 {"Name": '{"namespace":"synthetic"}'},
                 {"Name": '{"namespace":"other","operationId":"alice:1","kind":"put"}'}]
        self.assertEqual(discover_operations(items, "synthetic"), {})

    def test_reused_operation_identifiers_do_not_silently_choose_a_payload(self):
        first = {"namespace": "synthetic", "operationId": "alice:1", "kind": "put"}
        second = {"namespace": "synthetic", "operationId": "alice:1", "kind": "delete"}
        with self.assertRaises(ValueError):
            discover_operations([{"Name": json.dumps(first)}, {"Name": json.dumps(second)}], "synthetic")
