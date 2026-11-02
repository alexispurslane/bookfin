"""The host runner keeps fingerprinted inputs unless regeneration is explicit."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


class RunnerInputs(unittest.TestCase):
    def run_mode(self, arguments):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copyfile(Path(__file__).with_name('run'), root / 'run')
            for directory in ['bin', 'fixtures', 'dart_pdf', 'dart_epub']:
                (root / directory).mkdir()
            fixture = root / 'fixtures/simple.pdf'
            fixture.write_bytes(b'committed fixture bytes')
            (root / 'alice.mobi').write_bytes(b'public domain input')
            # External engines are irrelevant to the runner's input lifetime.
            for command in ['tar', 'mobitool', 'unzip', 'dart']:
                stub = root / 'bin' / command
                stub.write_text('#!/bin/sh\nexit 0\n')
                stub.chmod(0o755)
            python = root / 'bin/python'
            python.write_text('#!/bin/sh\nif [ "$1" = fixtures.py ]; then printf regenerated > fixtures/simple.pdf; fi\n')
            python.chmod(0o755)
            environment = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}",
                               PDFIUM_HOST_ARCHIVE='host', PDFIUM_ANDROID_ARCHIVE='android',
                               ALICE_KF8=str(root / 'alice.mobi'))
            subprocess.run(['bash', str(root / 'run'), *arguments], env=environment,
                           check=True, capture_output=True)
            return fixture.read_bytes()

    def test_fingerprinted_run_preserves_committed_fixture_bytes(self):
        self.assertEqual(self.run_mode(['--keep-fixtures']), b'committed fixture bytes')

    def test_explicit_regeneration_replaces_fixture_bytes(self):
        self.assertEqual(self.run_mode(['--regenerate-fixtures']), b'regenerated')


if __name__ == '__main__':
    unittest.main()
