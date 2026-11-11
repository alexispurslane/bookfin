import copy
import unittest

from results import BOUNDARY, ENGINES, OPERATIONS, summarize


def sample(number=0, **changes):
    row = {
        "id": f"sample-{number}", "engine": "bookfin", "book": "prose",
        "operation": "page_turn", "round": 0, "sequence": number,
        "warmup": False, "cache": "warm_document", "boundary": BOUNDARY,
        "start_ns": 1000000, "end_ns": 1000000 + (number + 1) * 1000000,
        "clock": "android_elapsed_realtime_ns", "expected": "chapter-1:page-2",
        "actual": "chapter-1:page-2", "text": "The requested page has real text.",
        "capture_sha256": "a" * 64, "reference_sha256": "a" * 64,
        "window_copy_verified": True, "content_verified": True,
        "run_id": "measured-run", "reference_run_id": "independent-calibration",
        "reference_manifest_sha256": "b" * 64,
        "error": None,
    }
    row.update(changes)
    return row


class ResultsTest(unittest.TestCase):
    def test_reports_median_and_nearest_rank_p90_in_milliseconds(self):
        result = summarize([sample(number) for number in range(10)])
        self.assertEqual(len(result["cells"]), 1)
        self.assertEqual(result["cells"][0]["median_ms"], 5.5)
        self.assertEqual(result["cells"][0]["p90_ms"], 9)
        self.assertEqual(result["cells"][0]["count"], 10)

    def test_keeps_books_operations_and_engines_separate(self):
        rows = [sample(), sample(1, book="long"), sample(2, engine="webview"),
                sample(3, operation="font_change", cache="warm_document")]
        self.assertEqual(len(summarize(rows)["cells"]), 4)

    def test_excludes_blank_stale_wrong_destination_and_error_samples(self):
        for changes in ({"text": " "}, {"capture_sha256": "b" * 64},
                        {"actual": "chapter-0:page-1"}, {"error": "load failed"},
                        {"end_ns": None}, {"end_ns": 0}, {"end_ns": float("nan")},
                        {"boundary": "relocated"}, {"clock": "host_wall_time"},
                        {"capture_sha256": "not-a-digest"}, {"expected": ""}):
            with self.subTest(changes=changes):
                result = summarize([sample(**changes)])
                self.assertEqual(result["cells"], [])
                self.assertEqual(len(result["excluded"]), 1)

    def test_excludes_warmups_and_preserves_their_reason(self):
        result = summarize([sample(warmup=True), sample(1)])
        self.assertEqual(result["excluded"][0]["reason"], "warmup")
        self.assertEqual(result["cells"][0]["count"], 1)

    def test_rejects_duplicate_ids_instead_of_counting_them_twice(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            summarize([sample(), sample()])

    def test_rejects_mixed_cache_states_in_one_cell(self):
        result = summarize([sample(), sample(1, cache="fresh_document")])
        self.assertEqual(result["cells"][0]["count"], 1)
        self.assertEqual(len(result["excluded"]), 1)

    def test_does_not_report_an_incomplete_matrix_as_complete(self):
        self.assertFalse(summarize([sample(number) for number in range(30)])["complete"])

    def test_complete_requires_all_engines_books_operations_and_counts(self):
        rows = []
        for engine in ENGINES:
            for book in ("prose", "long", "illustrated"):
                for operation in OPERATIONS:
                    count = 10 if operation == "fresh_open" else 30
                    cache = "fresh_document" if operation == "fresh_open" else "warm_document"
                    for number in range(count):
                        row = sample(number, engine=engine, book=book, operation=operation,
                                     cache=cache, round=number % 10)
                        row["id"] = f"{engine}/{book}/{operation}/{number}"
                        rows.append(row)
        self.assertTrue(summarize(rows)["complete"])
        rows.pop()
        self.assertFalse(summarize(rows)["complete"])

    def test_preserves_input_rows_without_mutation(self):
        rows = [sample(), sample(1, error="failure")]
        original = copy.deepcopy(rows)
        summarize(rows)
        self.assertEqual(rows, original)

    def test_unverified_content_or_presentation_cannot_enter_the_summary(self):
        for changes in ({"window_copy_verified": False}, {"content_verified": False}):
            result = summarize([sample(**changes)])
            self.assertEqual(result["cells"], [])
            self.assertEqual(len(result["excluded"]), 1)

    def test_missing_round_information_is_an_exclusion_not_a_crash(self):
        row = sample()
        del row["round"]
        result = summarize([row])
        self.assertEqual(result["cells"], [])
        self.assertEqual(len(result["excluded"]), 1)

    def test_a_capture_cannot_certify_itself_as_a_reference(self):
        result = summarize([sample(reference_run_id="measured-run")])
        self.assertEqual(result["cells"], [])
        self.assertIn("independent", result["excluded"][0]["reason"])

    def test_reference_provenance_is_required_even_when_pixel_hashes_match(self):
        for changes in ({"reference_run_id": None}, {"reference_manifest_sha256": None}):
            self.assertEqual(summarize([sample(**changes)])["cells"], [])


if __name__ == "__main__":
    unittest.main()
