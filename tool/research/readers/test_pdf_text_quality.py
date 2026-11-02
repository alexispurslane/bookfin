"""Readable-text decisions, not character-retention claims."""

import json
import os
from pathlib import Path
import tempfile
import unittest
import subprocess

from corpus_inputs import verify_input
from fixtures import FIXTURES
from proof import anchor_for, extract_pdf, reflow_pdf, resolve_anchor
from pdf_text_quality import assess_page
import corpus_probe


ROOT = Path(__file__).resolve().parent


class TextQualityBoundary(unittest.TestCase):
    def rendered_text(self, blocks, width=720):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "reading.pdf"
            reflow_pdf(blocks, destination, width)
            return subprocess.run(["pdftotext", "-raw", str(destination), "-"], check=True, capture_output=True, text=True, timeout=30).stdout

    def test_absent_text_does_not_create_an_empty_successful_reading_view(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "reading.pdf"
            with self.assertRaisesRegex(ValueError, "absent"):
                reflow_pdf(extract_pdf(FIXTURES / "scanned.pdf"), destination, 360)
            self.assertFalse(destination.exists())

    def test_source_line_wrapping_does_not_force_a_new_paragraph(self):
        blocks = extract_pdf(FIXTURES / "simple.pdf")
        self.assertIn("road. A reader", self.rendered_text(blocks))

    def test_source_pages_keep_their_order_even_when_blocks_arrive_in_reverse(self):
        blocks = extract_pdf(FIXTURES / "simple.pdf")
        text = self.rendered_text(list(reversed(blocks)))
        self.assertLess(text.index("River chapter 1"), text.index("River chapter 2"))

    def test_a_large_footer_stays_below_the_body_instead_of_becoming_a_title(self):
        blocks = [block for block in extract_pdf(FIXTURES / "simple.pdf") if block["page"] == 0]
        footer = dict(blocks[0], text="Footer retained", baseline=20)
        text = self.rendered_text([footer, *blocks])
        self.assertGreater(text.index("Footer retained"), text.index("saved source location."))

    def test_a_long_reading_paragraph_continues_on_generated_pages_without_clipping(self):
        block = extract_pdf(FIXTURES / "simple.pdf")[1]
        text = self.rendered_text([dict(block, text="Readable paragraph. " * 160)], 360)
        self.assertEqual(" ".join(text.split()).count("Readable paragraph."), 160)

    def test_observed_source_errors_are_separate_from_geometry_errors(self):
        blocks = [block for block in extract_pdf(FIXTURES / "simple.pdf") if block["page"] == 0]
        unchecked = assess_page(blocks)
        observed = assess_page(blocks, source_layer_errors=["Independent comparison found a missing letter"])
        self.assertEqual(unchecked["source_layer"], "unchecked")
        self.assertEqual(unchecked["view"], "reflow")
        self.assertEqual(observed["reasons"], ["observed-source-layer-errors"])
        self.assertEqual(observed["view"], "original-page")

    def test_paragraphs_never_join_across_source_page_boundaries(self):
        blocks = extract_pdf(FIXTURES / "simple.pdf")
        with self.assertRaisesRegex(ValueError, "one source page"):
            assess_page(blocks)

    def test_simple_paragraphs_preserve_every_original_character_anchor(self):
        blocks = [block for block in extract_pdf(FIXTURES / "simple.pdf") if block["page"] == 0]
        decision = assess_page(blocks)
        self.assertEqual(len(decision["paragraphs"]), 2)
        retained = [block for paragraph in decision["paragraphs"] for block in paragraph["source_blocks"]]
        self.assertEqual(retained, blocks)
        self.assertIs(retained[1], blocks[1])

    def test_future_offline_ocr_requires_absent_or_independently_bad_source_text(self):
        blocks = [block for block in extract_pdf(FIXTURES / "simple.pdf") if block["page"] == 0]
        self.assertEqual(assess_page([]).get("future_ocr_reason"), "absent-text")
        self.assertEqual(assess_page(blocks, source_layer_errors=["Missing letter in the source layer"]).get("future_ocr_reason"), "observed-source-layer-errors")
        self.assertIsNone(assess_page(blocks).get("future_ocr_reason"))


@unittest.skipUnless(os.environ.get("BOOKFIN_REAL_CORPUS") == "1", "Acquire the exact public corpus first")
class PinnedTextQuality(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = {}
        cls.blocks = {}
        manifest = json.loads((ROOT / "corpus-manifest.json").read_text())
        for sample in manifest["samples"]:
            if sample["filename"].endswith(".pdf"):
                path = ROOT / "_out/corpus/originals" / sample["filename"]
                verify_input(path, sample)
                cls.inputs[sample["id"]] = path
                cls.blocks[sample["id"]] = extract_pdf(path)

    def page(self, name, number):
        return [block for block in self.blocks[name] if block["page"] == number - 1]

    def assert_fallback(self, blocks):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "reading.pdf"
            with self.assertRaisesRegex(ValueError, "unreliable"):
                reflow_pdf(blocks, destination, 360)
            self.assertFalse(destination.exists())

    def test_census_first_page_cannot_present_cross_column_combinations_as_reading(self):
        blocks = self.page("census-multicolumn-pdf", 1)
        self.assertTrue(any("gender expression" in block["text"] and "Census Bureau" in block["text"] for block in blocks))
        self.assert_fallback(blocks)

    def test_nist_numbered_headings_do_not_disable_useful_single_flow_text(self):
        blocks = self.page("nist-text-pdf", 5)
        self.assertEqual(assess_page(blocks)["view"], "reflow")

    def test_nist_paragraphs_retain_headings_footer_and_a_source_anchor_at_both_widths(self):
        path = self.inputs["nist-text-pdf"]
        blocks = self.page("nist-text-pdf", 5)
        decision = assess_page(blocks)
        paragraphs = decision["paragraphs"]
        self.assertEqual(paragraphs[0]["text"], "1. Introduction")
        self.assertEqual(paragraphs[-1]["text"], "1")
        self.assertIn("Public Law 107-347.", paragraphs[2]["text"])
        anchor = anchor_for(path, blocks, "NIST is responsible")
        self.assertIsNotNone(anchor)
        self.assertEqual(anchor["page"], 4)
        with tempfile.TemporaryDirectory() as directory:
            lines = [reflow_pdf(blocks, Path(directory) / f"{width}.pdf", width) for width in (360, 720)]
        self.assertGreater(lines[0], lines[1])
        self.assertTrue(resolve_anchor(path, blocks, anchor).startswith("NIST is responsible"))

    def test_extraction_order_errors_alone_do_not_blame_the_source_text_layer(self):
        decision = assess_page(self.page("census-multicolumn-pdf", 1))
        self.assertIn("discontinuous-source-order", decision["reasons"])
        self.assertEqual(decision["source_layer"], "unchecked")
        self.assertIsNone(decision["future_ocr_reason"])

    def test_census_continuation_page_also_requires_its_complete_original(self):
        blocks = self.page("census-multicolumn-pdf", 2)
        self.assertTrue(any("Census Bureau" in block["text"] and "FTZ" in block["text"] for block in blocks))
        self.assert_fallback(blocks)

    def test_raven_opening_verse_cannot_present_37_fragments_as_reading(self):
        blocks = self.page("raven-1873-scan", 9)
        self.assertEqual(len(blocks), 37)
        self.assertIn("NCE", [block["text"] for block in blocks])
        self.assertNotIn("ONCE", [block["text"] for block in blocks])
        self.assert_fallback(blocks)

    def test_a_short_fragmented_raven_stamp_is_not_mistaken_for_a_readable_paragraph(self):
        blocks = self.page("raven-1873-scan", 24)
        self.assertEqual(len(blocks), 9)
        self.assertIn("LIBRARY", [block["text"] for block in blocks])
        self.assert_fallback(blocks)

    def test_the_retained_image_only_raven_page_is_absent_not_a_bad_text_layer(self):
        path = ROOT / "evidence/text-quality/raven-raster-only.pdf"
        sample = json.loads((ROOT / "evidence/corpus/python-observations.json").read_text())["raven_raster_only_derivative"]
        verify_input(path, sample)
        decision = assess_page(extract_pdf(path))
        self.assertEqual(decision["status"], "absent")
        self.assertEqual(decision["source_layer"], "unchecked")
        self.assertEqual(decision["reasons"], [])

    def test_the_research_probe_reports_fallback_instead_of_aborting_or_measuring_bad_reflow(self):
        previous = corpus_probe.OUT
        try:
            with tempfile.TemporaryDirectory() as directory:
                corpus_probe.OUT = Path(directory)
                try:
                    result = corpus_probe.inspect_pdf({"id": "census-multicolumn-pdf", "expected_phrases": ["nominations"]}, self.inputs["census-multicolumn-pdf"])
                except ValueError as error:
                    self.fail(f"The probe must report original-page fallback, not abort: {error}")
                self.assertEqual(result["sampled_page_layout_by_width_pdf_points"]["360"]["status"], "original-page")
                self.assertFalse((Path(directory) / "census-multicolumn-pdf-reflow-360.pdf").exists())
                self.assertTrue((Path(directory) / "census-multicolumn-pdf-source.png").exists())
        finally:
            corpus_probe.OUT = previous


if __name__ == "__main__":
    unittest.main()
