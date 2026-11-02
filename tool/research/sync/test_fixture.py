import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import tempfile
import threading
import unittest

from fixture import Api, is_ready, private_json, require_download, validate_origin


class DisposableSafetyTests(unittest.TestCase):
    def test_startup_status_without_a_server_identity_is_not_ready(self):
        self.assertFalse(is_ready({"Message": "Server is starting"}))
        self.assertFalse(is_ready({"Version": "12.4.0"}))
        self.assertFalse(is_ready({"Version": "12.3.0", "Id": "synthetic"}))
        self.assertTrue(is_ready({"Version": "12.4.0", "Id": "synthetic"}))

    def test_a_denied_download_never_falls_back_to_file(self):
        requested_paths = []

        class DenyDownload(BaseHTTPRequestHandler):
            def do_GET(self):
                requested_paths.append(self.path)
                self.send_response(403)
                self.end_headers()

            def log_message(self, *arguments):
                pass

        with HTTPServer(("127.0.0.1", 0), DenyDownload) as server:
            worker = threading.Thread(target=server.handle_request)
            worker.start()
            status, headers, body = Api(origin=f"http://127.0.0.1:{server.server_port}").download("synthetic", {"EnableContentDownloading": True})
            worker.join(timeout=5)
        self.assertEqual(status, 403)
        self.assertEqual(requested_paths, ["/Items/synthetic/Download"])

    def test_redirects_do_not_forward_the_token_or_start_another_request(self):
        requested_paths = []

        class Redirect(BaseHTTPRequestHandler):
            def do_GET(self):
                requested_paths.append(self.path)
                self.send_response(302)
                self.send_header("Location", "/second")
                self.end_headers()

            def log_message(self, *arguments):
                pass

        with HTTPServer(("127.0.0.1", 0), Redirect) as server:
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                status, headers, body = Api("synthetic", f"http://127.0.0.1:{server.server_port}").request("GET", "/first")
                self.assertEqual(status, 302)
                self.assertEqual(requested_paths, ["/first"])
            finally:
                server.shutdown()
                worker.join(timeout=5)

    def test_credential_output_cannot_follow_a_symbolic_link(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "unrelated.json"
            target.write_text("unchanged")
            link = Path(directory) / "credentials.json"
            link.symlink_to(target)
            with self.assertRaises(OSError):
                private_json(link, {"Password": "synthetic"})
            self.assertEqual(target.read_text(), "unchanged")

    def test_missing_download_permission_stops_the_actual_http_transfer(self):
        requested_paths = []

        class CaptureDownload(BaseHTTPRequestHandler):
            def do_GET(self):
                requested_paths.append(self.path)
                self.send_response(403)
                self.end_headers()

            def log_message(self, *arguments):
                pass

        with HTTPServer(("127.0.0.1", 0), CaptureDownload) as server:
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                api = Api(origin=f"http://127.0.0.1:{server.server_port}")
                with self.assertRaises(PermissionError):
                    api.download("synthetic", {})
                self.assertEqual(requested_paths, [])
            finally:
                server.shutdown()
                worker.join(timeout=5)

    def test_authentication_works_without_jellyfins_legacy_token_header(self):
        class CaptureHeaders(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"modernToken": 'Token="synthetic-token"' in self.headers.get("Authorization", "")}).encode())

            def log_message(self, *arguments):
                pass

        with HTTPServer(("127.0.0.1", 0), CaptureHeaders) as server:
            worker = threading.Thread(target=server.handle_request)
            worker.start()
            result = Api("synthetic-token", f"http://127.0.0.1:{server.server_port}").json("GET", "/")
            worker.join(timeout=5)
        self.assertTrue(result["modernToken"])

    def test_production_and_nonliteral_hosts_are_rejected_before_any_request(self):
        for origin in ["https://jellyfin.example.com", "http://localhost:7364",
                       "http://0.0.0.0:7364", "http://192.168.1.2:7364",
                       "http://127.0.0.1.example.org:7364"]:
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                validate_origin(origin)

    def test_only_bare_loopback_http_origins_are_accepted(self):
        self.assertEqual(validate_origin("http://127.0.0.1:7364"), "http://127.0.0.1:7364")
        for origin in ["http://user:pass@127.0.0.1:7364", "http://127.0.0.1:7364/a",
                       "http://127.0.0.1:7364?token=a", "http://127.0.0.1:7364#fragment"]:
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                validate_origin(origin)

    def test_download_is_denied_when_permission_is_false_missing_or_not_a_boolean(self):
        for policy in [{}, {"EnableContentDownloading": False},
                       {"EnableContentDownloading": "true"}, {"EnableContentDownloading": 1}]:
            with self.subTest(policy=policy), self.assertRaises(PermissionError):
                require_download(policy)
        require_download({"EnableContentDownloading": True})

    def test_generated_credentials_are_private_even_when_replacing_a_public_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "credentials.json"
            path.write_text("{}")
            os.chmod(path, 0o644)
            private_json(path, {"Password": "generated-only"})
            self.assertEqual(json.loads(path.read_text()), {"Password": "generated-only"})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
