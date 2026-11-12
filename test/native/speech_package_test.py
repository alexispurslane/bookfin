"""The package check refuses an APK whose speech model is missing, changed
or compressed. Run by test/native/speech_package_test.sh."""

import hashlib
import io
import sys
import unittest
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tool/reader'))
import speech_package  # noqa: E402

MODEL = b'ggml model bytes ' * 64
PIN = hashlib.sha256(MODEL).hexdigest()


def apk(entries):
    """An in-memory APK with [entries]: (name, bytes, compression)."""
    buffer = io.BytesIO()
    with ZipFile(buffer, 'w') as archive:
        for name, payload, compression in entries:
            archive.writestr(name, payload, compress_type=compression)
    buffer.seek(0)
    return ZipFile(buffer)


class ModelCheck(unittest.TestCase):
    def test_accepts_the_pinned_model_stored_uncompressed(self):
        archive = apk([(speech_package.ASSET, MODEL, ZIP_STORED)])
        self.assertEqual(speech_package.check_model(archive, PIN), len(MODEL))

    def test_refuses_an_apk_without_the_model(self):
        archive = apk([('assets/other.bin', MODEL, ZIP_STORED)])
        with self.assertRaisesRegex(ValueError, 'speech model'):
            speech_package.check_model(archive, PIN)

    def test_refuses_a_changed_model(self):
        archive = apk([(speech_package.ASSET, MODEL + b'!', ZIP_STORED)])
        with self.assertRaisesRegex(ValueError, 'changed'):
            speech_package.check_model(archive, PIN)

    def test_refuses_a_compressed_model_that_cannot_load_in_place(self):
        archive = apk([(speech_package.ASSET, MODEL, ZIP_DEFLATED)])
        with self.assertRaisesRegex(ValueError, 'uncompressed'):
            speech_package.check_model(archive, PIN)

    def test_refuses_a_second_model(self):
        archive = apk([
            (speech_package.ASSET, MODEL, ZIP_STORED),
            ('assets/bookfin-speech/base.en.ggml', MODEL, ZIP_STORED),
        ])
        with self.assertRaisesRegex(ValueError, 'only the selected'):
            speech_package.check_model(archive, PIN)


if __name__ == '__main__':
    unittest.main()
