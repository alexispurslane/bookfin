import io
import unittest

import android_proxy


class AndroidProxyTests(unittest.TestCase):
    def test_chunked_flutter_requests_reach_jellyfin_with_their_body(self):
        self.assertEqual(android_proxy.request_body(
            {'Transfer-Encoding': 'chunked'}, io.BytesIO(b'4\r\nbook\r\n3\r\nfin\r\n0\r\n\r\n')),
            b'bookfin')

    def test_fixed_length_requests_retain_the_exact_bytes(self):
        self.assertEqual(android_proxy.request_body(
            {'Content-Length': '7'}, io.BytesIO(b'bookfin')),
            b'bookfin')

    def test_report_evidence_omits_unknown_fields_and_credentials(self):
        evidence = android_proxy.safe_report({
            'ItemId': 'synthetic-item', 'MediaSourceId': 'synthetic-source',
            'PositionTicks': 420000, 'IsPaused': True,
            'AccessToken': 'private', 'PlaySessionId': 'private-session',
            'Unexpected': {'password': 'private'},
        })
        self.assertEqual(evidence, {
            'ItemId': 'synthetic-item', 'MediaSourceId': 'synthetic-source',
            'PositionTicks': 420000, 'IsPaused': True,
        })

    def test_only_origin_relative_paths_can_reach_the_disposable_server(self):
        for path in ['http://example.org/Items', '//example.org/Items', 'Items']:
            with self.subTest(path=path):
                self.assertFalse(android_proxy.safe_path(path))
        self.assertTrue(android_proxy.safe_path('/Items/synthetic/Download'))

    def test_query_credentials_cannot_enter_evidence(self):
        self.assertEqual(
            android_proxy.evidence_path('/Items/synthetic/Download?api_key=private'),
            '/Items/synthetic/Download',
        )


if __name__ == '__main__':
    unittest.main()
