"""Disposable HTTP proof of the additive batch contract; never a live server."""
from contextlib import closing
import json
import sqlite3
import unittest

from dedicated_fixture import Api, ORIGIN, Server

BASE = '/BookfinStorage/v2/objects'
LEGACY = '/BookfinStorage/v1/objects'


class BatchStorage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Server()
        cls.addClassCleanup(cls.server.stop)
        cls.server.start()
        cls.server.seed()

    def batch(self, objects, name='alice'):
        return self.server.api(name).request('PUT', BASE, {'Objects': objects})

    def test_01_legacy_clients_keep_their_routes_and_four_object_pages(self):
        alice = self.server.api('alice')
        self.assertEqual(alice.request('PUT', LEGACY + '/legacy', {'Payload': 'original'})[0], 201)
        page = alice.json('GET', LEGACY)
        self.assertRegex(page.get('PluginVersion', ''), r'^0\.[2-9]\.\d+\.\d+$')
        self.assertLessEqual(len(page['Objects']), 4)
        self.assertEqual(alice.request('GET', LEGACY + '?limit=5')[0], 400)
        self.assertEqual(alice.request('PUT', LEGACY + '/legacy', {'Payload': 'changed'})[0], 409)

    def test_02_batch_retries_share_single_object_immutability_and_deletion_rules(self):
        alice = self.server.api('alice')
        self.assertEqual(alice.request('PUT', LEGACY + '/kept', {'Payload': 'original'})[0], 201)
        self.assertEqual(alice.request('DELETE', LEGACY + '/deleted')[0], 204)
        items = [{'Id': 'kept', 'Payload': 'changed'}, {'Id': 'deleted', 'Payload': 'late'},
                 {'Id': 'new', 'Payload': '\0opaque é'}]
        status, _, body = self.batch(items)
        self.assertEqual(status, 200)
        results = json.loads(body)['Results']
        self.assertEqual([r['Status'] for r in results], [409, 410, 201])
        original = results[2]['Object']
        status, _, body = self.batch([items[2]])
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['Results'][0], {'Id': 'new', 'Status': 200, 'Object': original})
        self.assertEqual(alice.json('GET', LEGACY + '/kept')['Payload'], 'original')
        self.assertEqual(alice.request('GET', LEGACY + '/deleted')[0], 410)

    def test_03_batch_identity_always_comes_from_the_authenticated_ordinary_user(self):
        self.assertEqual(self.batch([{'Id': 'private-batch', 'Payload': 'alice'}])[0], 200)
        bob = self.server.api('bob')
        forged = BASE + '?userId=' + self.server.accounts['alice']['id']
        self.assertEqual(bob.request('PUT', forged, {'Objects': [{'Id': 'private-batch', 'Payload': 'bob'}]})[0], 200)
        self.assertEqual(self.server.api('alice').json('GET', LEGACY + '/private-batch')['Payload'], 'alice')
        self.assertEqual(bob.json('GET', LEGACY + '/private-batch')['Payload'], 'bob')
        for method, body in [('GET', None), ('PUT', {'Objects': [{'Id': 'denied', 'Payload': 'no'}]})]:
            self.assertEqual(Api(origin=ORIGIN).request(method, BASE, body)[0], 401)

    def test_04_invalid_batches_change_nothing_and_enforce_count_and_utf8_byte_limits(self):
        alice = self.server.api('alice')
        for items, expected in [
            ([], 400), ([{'Id': str(i), 'Payload': 'x'} for i in range(257)], 400),
            ([{'Id': 'valid-before-invalid', 'Payload': 'valid'}, {'Id': 'bad!', 'Payload': 'bad'}], 400),
            ([{'Id': 'duplicate', 'Payload': 'a'}, {'Id': 'duplicate', 'Payload': 'b'}], 400),
            ([{'Id': 'large', 'Payload': 'é' * 32769}], 413),
            ([{'Id': 'large-' + str(i), 'Payload': 'x' * 65536} for i in range(17)], 413),
        ]:
            self.assertEqual(self.batch(items)[0], expected)
        self.assertEqual(alice.request('GET', LEGACY + '/valid-before-invalid')[0], 404)
        self.assertEqual(alice.request('GET', BASE + '?limit=257')[0], 400)

    def test_05_a_server_transaction_failure_rolls_back_the_whole_batch(self):
        path, = (self.server.root / 'data').rglob('bookfin-storage-v1.sqlite')
        with closing(sqlite3.connect(path)) as sql:
            sql.execute("CREATE TRIGGER fail_batch BEFORE INSERT ON objects WHEN NEW.identity='rollback-2' BEGIN SELECT RAISE(ABORT, 'simulated disk full'); END")
            sql.commit()
        items = [{'Id': 'rollback-1', 'Payload': 'one'}, {'Id': 'rollback-2', 'Payload': 'two'}]
        try:
            self.assertEqual(self.batch(items)[0], 500)
            self.assertEqual(self.server.api('alice').request('GET', LEGACY + '/rollback-1')[0], 404)
        finally:
            with closing(sqlite3.connect(path)) as sql:
                sql.execute('DROP TRIGGER fail_batch')
                sql.commit()
        self.assertEqual(self.batch(items)[0], 200)

    def test_06_thousands_of_objects_are_discovered_after_upgrade_and_restart_with_bounded_pages(self):
        alice = self.server.api('alice')
        original = {f'workload-{i}': f'action-{i}' for i in range(2400)}
        items = [{'Id': key, 'Payload': value} for key, value in original.items()]
        for start in range(0, len(items), 256):
            self.assertEqual(self.batch(items[start:start + 256])[0], 200)
        self.server.stop()
        self.server.start()
        received = {}
        cursor = 0
        requests = 0
        while True:
            page = alice.json('GET', BASE + f'?after={cursor}&limit=256')
            requests += 1
            self.assertLessEqual(len(page['Objects']), 256)
            self.assertLessEqual(sum(len((item['Payload'] or '').encode()) for item in page['Objects']), 1048576)
            received.update({item['Id']: item['Payload'] for item in page['Objects'] if item['Id'].startswith('workload-')})
            if not page['HasMore']:
                break
            self.assertGreater(page['Cursor'], cursor)
            cursor = page['Cursor']
            self.assertLess(requests, 20)
        self.assertEqual(received, original)
        self.assertLessEqual(requests, 11)


if __name__ == '__main__':
    unittest.main()
