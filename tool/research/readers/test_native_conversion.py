import ctypes
import os
from pathlib import Path
import tempfile
import unittest
import zipfile


class AndroidConversionBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = ctypes.CDLL(os.environ["BOOKFIN_CONVERTER"])
        cls.convert = cls.library.bookfin_convert
        cls.convert.argtypes = [ctypes.c_char_p]
        cls.convert.restype = ctypes.c_int

    def test_supported_variants_create_readable_epub_with_text_and_images(self):
        for path in [Path("fixtures/mobi6-plain.mobi"),
                     Path("fixtures/mobi6-palmdoc.mobi"),
                     Path("fixtures/pg11-kf8.mobi")]:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as folder:
                original = Path(folder) / path.name
                original.write_bytes(path.read_bytes())
                self.assertEqual(self.convert(os.fsencode(original)), 0)
                destination = original.with_suffix(".epub")
                self.assertTrue(destination.is_file(), "conversion must write an EPUB, not merely parse MOBI")
                with zipfile.ZipFile(destination) as book:
                    self.assertEqual(book.read("mimetype"), b"application/epub+zip")
                    text = b"".join(book.read(name) for name in book.namelist()
                                    if name.endswith((".html", ".xhtml")))
                    self.assertIn(b"Alice" if "kf8" in path.name else b"The river", text)
                    self.assertTrue(any(name.endswith((".png", ".jpeg", ".jpg", ".gif"))
                                        for name in book.namelist()))
                self.assertEqual(original.read_bytes(), path.read_bytes())

    def test_malformed_input_reports_failure_without_creating_an_epub(self):
        with tempfile.TemporaryDirectory() as folder:
            original = Path(folder) / "broken.mobi"
            original.write_bytes(b"not a MOBI book")
            self.assertNotEqual(self.convert(os.fsencode(original)), 0)
            self.assertFalse(original.with_suffix(".epub").exists())


if __name__ == "__main__":
    unittest.main()
