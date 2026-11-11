import copy
import unittest

from results import summarize
from test_results import sample
from test_validation import raw, reference
from validation import certify


def prepared(number=0, **changes):
    row = sample(number, id=f"measured-run/{number}", sequence=number,
                 preparation_event_id=f"measured-run/{number}",
                 preparation_operation="page_turn", operation_returned_ns=1_200_000,
                 preparation_ns=1_500_000, engine_ready_ns=1_600_000,
                 preparation_scope="flutter_picture_and_decoded_page_images",
                 phase_clock={"source": "dart_timeline_us", "offset_ns": 0,
                              "uncertainty_ns": 1000},
                 start_source_us=1000, operation_returned_source_us=1200,
                 preparation_source_us=1500,
                 end_ns=10_000_000)
    row.update(changes)
    if type(row["preparation_ns"]) is int and "preparation_source_us" not in changes:
        row["preparation_source_us"] = row["preparation_ns"] // 1000
    return row


def milestone(rows, name="preparation"):
    return summarize(rows).get("milestones", {}).get(name, {})


class PreparationTimingTest(unittest.TestCase):
    def test_preparation_stops_at_the_engine_event_before_the_window_copy(self):
        cells = milestone([prepared()]).get("cells", [])
        self.assertEqual(len(cells), 1)
        self.assertEqual(cells[0]["mean_ms"], .5)
        self.assertEqual(cells[0]["scope"], "flutter_picture_and_decoded_page_images")

    def test_delaying_capture_does_not_move_either_engine_milestone(self):
        early = prepared()
        late = prepared(end_ns=90_000_000)
        self.assertEqual(milestone([early]), milestone([late]))
        self.assertEqual(milestone([early], "operation_returned"),
                         milestone([late], "operation_returned"))
        self.assertNotEqual(summarize([early])["cells"], summarize([late])["cells"])

    def test_stale_readiness_never_becomes_an_accepted_preparation_sample(self):
        for changes in ({"preparation_event_id": "previous-run/0"},
                        {"preparation_operation": "cached_reopen"}):
            with self.subTest(changes=changes):
                result = milestone([prepared(**changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_missing_reversed_or_out_of_order_endpoints_are_excluded(self):
        for changes in ({"preparation_ns": None}, {"preparation_ns": 999_999},
                        {"preparation_ns": 11_000_000},
                        {"operation_returned_ns": 1_700_000},
                        {"preparation_ns": True}, {"preparation_ns": float("nan")},
                        {"preparation_scope": "webview_layout_fonts_and_decoded_section_images"},
                        {"phase_clock": {"source": "host_wall_time", "offset_ns": 0, "uncertainty_ns": 0}}):
            with self.subTest(changes=changes):
                result = milestone([prepared(**changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_wrong_pixels_text_and_destination_exclude_preparation_after_certification(self):
        for changes in ({"capture_sha256": "d" * 64}, {"visible_text": "wrong chapter"},
                        {"location": "epubcfi(/6/2!/4)"}):
            with self.subTest(changes=changes):
                row = {**prepared(), **raw(**changes)}
                certified = certify([row], reference(), "c" * 64)
                result = milestone(certified)
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_mean_weights_each_book_once_even_when_sample_counts_differ(self):
        rows = [prepared(preparation_ns=2_000_000, engine_ready_ns=2_100_000),
                prepared(1, book="long", preparation_ns=4_000_000, engine_ready_ns=4_100_000),
                prepared(2, book="long", preparation_ns=6_000_000, engine_ready_ns=6_100_000),
                prepared(3, book="illustrated", preparation_ns=10_000_000,
                         engine_ready_ns=10_100_000, end_ns=11_000_000)]
        means = milestone(rows).get("equal_book_means", [])
        self.assertEqual(len(means), 1)
        self.assertAlmostEqual(means[0]["mean_ms"], (1 + 4 + 9) / 3)
        self.assertEqual(means[0]["book_count"], 3)

    def test_unavailable_preparation_is_not_filled_from_legacy_engine_ready(self):
        row = prepared()
        del row["preparation_ns"]
        self.assertEqual(milestone([row]).get("cells", []), [])
        self.assertEqual(len(summarize([row])["cells"]), 1)

    def test_engine_clocks_convert_raw_events_without_using_bridge_receipt_time(self):
        for engine, scope, clock, source in (
                ("webview", "webview_layout_fonts_and_decoded_section_images",
                 "web_performance_ms", {"operation_returned_source_ms": .2, "preparation_source_ms": .5}),
                ("koreader", "koreader_drawn_page_bitmap", "android_boottime_ns", {})):
            with self.subTest(engine=engine):
                row = prepared(engine=engine, preparation_scope=scope, **source,
                               phase_clock={"source": clock, "offset_ns": 1_000_000 if engine == "webview" else 0,
                                            "uncertainty_ns": 1000 if engine == "webview" else 0})
                self.assertEqual(len(milestone([row]).get("cells", [])), 1)

    def test_wrong_conversion_and_missing_source_timestamps_are_excluded(self):
        for changes in ({"preparation_source_us": 1501}, {"preparation_source_us": None},
                        {"operation_returned_source_us": float("inf")},
                        {"start_source_us": 999}):
            with self.subTest(changes=changes):
                result = milestone([prepared(**changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_summary_does_not_rewrite_retained_raw_phase_timestamps(self):
        rows = [prepared()]
        original = copy.deepcopy(rows)
        summarize(rows)
        self.assertEqual(rows, original)


if __name__ == "__main__":
    unittest.main()
