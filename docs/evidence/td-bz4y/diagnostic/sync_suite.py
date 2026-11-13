"""Run the applicable sync suite; explicitly skip tests that start HTTP servers."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "tool/research/sync"))
from test_fixture import DisposableSafetyTests
from test_playlist_protocol import PrivacyEvidenceTests
from test_finite_runtime import InventoryTests

reason = "td-bz4y prohibits server actions; this test starts a local HTTP server"
for cls in (PrivacyEvidenceTests, InventoryTests):
    unittest.skip(reason)(cls)
for name in (
    "test_a_denied_download_never_falls_back_to_file",
    "test_redirects_do_not_forward_the_token_or_start_another_request",
    "test_missing_download_permission_stops_the_actual_http_transfer",
    "test_authentication_works_without_jellyfins_legacy_token_header",
):
    setattr(DisposableSafetyTests, name, unittest.skip(reason)(getattr(DisposableSafetyTests, name)))

loader = unittest.defaultTestLoader
suite = (loader.loadTestsFromTestCase(DisposableSafetyTests) if sys.argv[1] == "focused"
         else loader.discover(str(ROOT / "tool/research/sync")))
result = unittest.TextTestRunner(verbosity=2).run(suite)
print(json.dumps({"testsRun": result.testsRun, "failures": len(result.failures),
                  "errors": len(result.errors), "skips": [(test.id(), why) for test, why in result.skipped]}))
sys.exit(not result.wasSuccessful())
