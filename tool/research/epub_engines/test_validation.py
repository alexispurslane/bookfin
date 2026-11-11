import unittest

from validation import certify


def raw(**changes):
    row = {"engine": "bookfin", "book": "prose", "case": "target18", "run_id": "round-0",
           "capture_sha256": "a" * 64, "location": "epubcfi(/6/10!/4/2)", "location_format": "epub_cfi",
           "visible_text": "Alice was beginning to get very tired", "text_size_css_px": 18,
           "book_sha256": "b" * 64, "pixel_copy_code": 0, "window_copy_verified": True,
           "reference_manifest_sha256": "c" * 64}
    row.update(changes)
    return row


def reference(**changes):
    row = {**raw(), "run_id": "calibration-prose", "source_validated": True,
           "ocr_validated": True, "image_reviewed": True, "spine_index": 4}
    row.update(changes)
    return {"bookfin/prose/target18": row}


class IndependentReferenceTest(unittest.TestCase):
    def test_independent_source_checked_reference_certifies_matching_window_content(self):
        row = certify([raw()], reference(), "c" * 64)[0]
        self.assertTrue(row.get("content_verified"))
        self.assertEqual(row.get("expected"), row.get("actual"))
        self.assertEqual(row.get("reference_run_id"), "calibration-prose")

    def test_self_reference_wrong_location_and_stale_images_never_certify(self):
        cases = [(raw(), reference(run_id="round-0")),
                 (raw(location="epubcfi(/6/2!/4)"), reference()),
                 (raw(capture_sha256="d" * 64), reference()),
                 (raw(visible_text="stale chapter text"), reference()),
                 (raw(text_size_css_px=20), reference()),
                 (raw(book_sha256="d" * 64), reference()),
                 (raw(), reference(source_validated=False)),
                 (raw(), reference(ocr_validated=False)),
                 (raw(), {})]
        for row, references in cases:
            with self.subTest(row=row, references=references):
                certified = certify([row], references, "c" * 64)[0]
                self.assertFalse(certified.get("content_verified", False))
                self.assertTrue(certified.get("error"))

    def test_a_different_reference_file_on_device_is_not_silently_accepted(self):
        row = raw(reference_manifest_sha256="d" * 64)
        self.assertTrue(certify([row], reference(), "c" * 64)[0].get("error"))

    def test_missing_device_manifest_provenance_cannot_be_supplied_by_the_collector(self):
        row = raw()
        del row["reference_manifest_sha256"]
        self.assertTrue(certify([row], reference(), "c" * 64)[0].get("error"))

    def test_preparation_is_preserved_but_not_counted_as_a_measurement(self):
        from results import summarize
        from test_results import sample
        self.assertEqual(summarize([sample(measured=False)])["cells"], [])
