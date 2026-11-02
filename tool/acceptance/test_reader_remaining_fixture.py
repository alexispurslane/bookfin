import tempfile
import unittest
import zipfile
from pathlib import Path

from reader_remaining_fixture import make_remaining_epub


class RemainingFixtureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        destination = Path(self.directory.name) / 'remaining.epub'
        make_remaining_epub(destination, b'synthetic-jpeg-placeholder')
        with zipfile.ZipFile(destination) as archive:
            self.entries = {name: archive.read(name) for name in archive.namelist()}

    def test_asset_chapter_distinguishes_direct_images_and_svg_fallbacks(self):
        chapter = self.entries['OEBPS/Text/one.xhtml'].decode()
        for label in ['Local PNG', 'Local JPEG', 'Exact JPEG wrapper', 'Active SVG']:
            self.assertIn(label, chapter)
        wrapper = self.entries['OEBPS/Images/wrapper.svg'].decode()
        self.assertIn('viewBox="0 0 2 3"', wrapper)
        self.assertNotIn('onload', wrapper)
        self.assertIn('onload', self.entries['OEBPS/Images/active.svg'].decode())

    def test_request_targets_are_bounded_owned_loopback_sinks(self):
        chapter = self.entries.get('OEBPS/Text/denial.xhtml', b'').decode()
        self.assertIn('http://127.0.0.1:7365/probe/', chapter)
        self.assertIn('<script>', chapter)
        self.assertIn('navigator.mediaDevices.getUserMedia', chapter)
        self.assertIn('<form', chapter)
        self.assertNotIn('evil.invalid', chapter)
        self.assertLess(sum(map(len, self.entries.values())), 300000)

    def test_reflow_chapter_contains_named_link_and_ordered_passages(self):
        chapter = self.entries.get('OEBPS/Text/reflow.xhtml', b'').decode()
        self.assertIn('Reflow passage 1.', chapter)
        self.assertLess(chapter.index('Reflow passage 1.'), chapter.index('Reflow passage 2.'))
        self.assertIn('Return to asset checks', chapter)
        self.assertIn('Select this sentence', chapter)

    def test_valid_asset_font_styles_are_separate_from_adversarial_styles(self):
        styles = self.entries['OEBPS/Styles/book.css'].decode()
        self.assertIn('Fonts/source-serif.woff2', styles)
        self.assertNotIn('/probe/', styles)
        self.assertIn('/probe/css', self.entries.get('OEBPS/Styles/denial.css', b'').decode())


if __name__ == '__main__':
    unittest.main()
