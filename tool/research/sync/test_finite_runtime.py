from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import unittest
import urllib.parse

from finite_runtime import inventory
from fixture import Api


class InventoryTests(unittest.TestCase):
    def check_inventory(self, remaining_count=False, incomplete_search=False):
        items = [{"Id": str(number), "Name": json.dumps({"namespace": "synthetic"})} for number in range(16)]

        class RemainingCountServer(BaseHTTPRequestHandler):
            def do_GET(self):
                query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
                start, limit = int(query["StartIndex"][0]), int(query["Limit"][0])
                available = items[4:] if incomplete_search and "SearchTerm" in query else items
                total = len(available) - start if remaining_count else len(available)
                body = json.dumps({"Items": available[start:start + limit], "TotalRecordCount": total}).encode()
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *arguments):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), RemainingCountServer) as server:
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                client = Api(origin=f"http://127.0.0.1:{server.server_port}")
                discovered, cost = inventory(client, "synthetic", 4)
                self.assertEqual(discovered, items)
                self.assertEqual(cost["requests"], 5)
            finally:
                server.shutdown()
                worker.join(timeout=5)

    def test_discovery_does_not_treat_remaining_count_as_the_original_total(self):
        self.check_inventory(remaining_count=True)

    def test_discovery_does_not_depend_on_search_results_for_a_complete_namespace(self):
        self.check_inventory(incomplete_search=True)
