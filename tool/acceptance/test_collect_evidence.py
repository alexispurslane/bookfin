import json
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect_evidence.py'))
collector = importlib.util.module_from_spec(spec)


class PublicationTests(unittest.TestCase):
    def test_failed_cleanup_cannot_publish_previously_recorded_success(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            runtime = repository / '.cache/sync/runtime'
            runtime.mkdir(parents=True)
            stale = runtime / 'app-results.json'
            stale.write_text(json.dumps({'serverId': 'fixture', 'results': {str(i): {'passed': True, 'http': []} for i in range(9)}}))
            (runtime / 'app-acceptance.json').write_text(json.dumps({'serverId': 'fixture', 'sources': {}}))
            (runtime / 'accounts.json').write_text('{}')
            (runtime / 'passwords.json').write_text('{}')
            pins = repository / 'tool/research/sync/sources.json'
            pins.parent.mkdir(parents=True)
            pins.write_text(json.dumps({'jellyfin': {}, 'nixpkgs': {'commit': 'fixture'}}))
            output = repository / 'tool/acceptance/evidence/app-http.json'
            output.parent.mkdir(parents=True)
            output.write_text('previous accepted evidence')

            def failed_cleanup(*args, **kwargs):
                self.assertFalse(stale.exists())
                stale.write_text('{"results":{"ninth":{"passed":true}}}')
                raise subprocess.CalledProcessError(1, args[0])

            with patch('subprocess.run', side_effect=failed_cleanup):
                with self.assertRaises(subprocess.CalledProcessError):
                    collector.publish(repository)
            self.assertEqual(output.read_text(), 'previous accepted evidence')


spec.loader.exec_module(collector)
