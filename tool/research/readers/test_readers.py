"""Boundary behavior, exercised against real generated files and real engines."""

from pathlib import Path
import tempfile
import unittest

from fixtures import FIXTURES
from proof import anchor_for, extract_pdf, reflow_pdf, resolve_anchor, safe_html


class ReadingProof(unittest.TestCase):
    def test_simple_pdf_exposes_text_and_source_pages(self):
        blocks = extract_pdf(FIXTURES / "simple.pdf")
        self.assertIn("The river follows the old road.", [block["text"] for block in blocks])
        self.assertEqual({block["page"] for block in blocks}, {0, 1})

    def test_two_columns_read_down_left_before_right(self):
        blocks = extract_pdf(FIXTURES / "columns.pdf")
        self.assertEqual([block["text"] for block in blocks], ["Two columns", "Left 1: the journey begins.", "Left 2: the journey begins.", "Left 3: the journey begins.", "Right 1: the journey ends.", "Right 2: the journey ends.", "Right 3: the journey ends."])

    def test_larger_pdf_title_is_a_heading_candidate(self):
        blocks = extract_pdf(FIXTURES / "simple.pdf")
        self.assertEqual([block["text"] for block in blocks if block["heading"]], ["River chapter 1", "River chapter 2"])

    def test_scanned_page_offers_no_fabricated_reflow_text(self):
        self.assertEqual(extract_pdf(FIXTURES / "scanned.pdf"), [])

    def test_saved_source_anchor_survives_a_layout_width_change(self):
        path = FIXTURES / "simple.pdf"
        blocks = extract_pdf(path)
        anchor = anchor_for(path, blocks, "old road")
        self.assertIsNotNone(anchor)
        with tempfile.TemporaryDirectory() as directory:
            narrow = reflow_pdf(blocks, Path(directory) / "narrow.pdf", 360)
            wide = reflow_pdf(blocks, Path(directory) / "wide.pdf", 720)
        self.assertGreater(narrow, wide)
        self.assertEqual(resolve_anchor(path, extract_pdf(path), anchor), "old road.")

    def test_replaced_file_does_not_reuse_an_old_anchor(self):
        path = FIXTURES / "simple.pdf"
        anchor = anchor_for(path, extract_pdf(path), "old road")
        self.assertIsNotNone(anchor)
        self.assertIsNone(resolve_anchor(FIXTURES / "columns.pdf", extract_pdf(FIXTURES / "columns.pdf"), anchor))

    def test_passive_html_keeps_local_images_headings_and_internal_links(self):
        html = safe_html((FIXTURES / "chapter.html").read_text(), FIXTURES)
        self.assertIn('<h1 id="river">River chapter</h1>', html)
        self.assertIn('src="dot.png"', html)
        self.assertIn('href="#river"', html)

    def test_active_or_remote_html_cannot_load(self):
        html = safe_html((FIXTURES / "chapter.html").read_text(), FIXTURES)
        for forbidden in ["<script", "onerror", "https:", "fetch("]:
            self.assertNotIn(forbidden, html)

    def test_local_asset_paths_cannot_escape_the_book(self):
        html = safe_html('<img src="../private.png"><img src="%2e%2e/private.png"><img src="file:///etc/passwd"><img src="//example.invalid/a"><img src="dot.png">', FIXTURES)
        self.assertEqual(html.count("src="), 1)
        self.assertIn('src="dot.png"', html)


if __name__ == "__main__":
    unittest.main(verbosity=2)
