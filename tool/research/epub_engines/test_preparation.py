import copy
import unittest

from results import summarize
from tables import PREPARED, book_table, _ms
from test_results import sample
from test_validation import raw, reference
from validation import certify


DRAWN_SCOPES = {"bookfin": "flutter_raster_finish_of_first_frame_with_page",
                "webview": "webview_visual_state_callback_after_preparation",
                "koreader": "koreader_cpu_drawn_page_bitmap"}
SCOPES = {"bookfin": "flutter_picture_and_decoded_page_images",
          "webview": "webview_layout_fonts_and_decoded_page_images",
          "koreader": "koreader_drawn_page_bitmap"}
CLOCKS = {"bookfin": {"source": "dart_timeline_us", "offset_ns": 0, "uncertainty_ns": 1000},
          "webview": {"source": "web_performance_ms", "offset_ns": 0, "uncertainty_ns": 101_000,
                      "observed_resolution_ns": 100_000},
          "koreader": {"source": "android_boottime_ns", "offset_ns": 0, "uncertainty_ns": 0}}


def prepared(number=0, engine="bookfin", vsync_ns=2_000_000, frame_ns=2_200_000, running=None, **changes):
    """A certified page turn: dispatch at 1.0 ms, engine entry at 1.1 ms,
    operation return at 1.2 ms, preparation at 1.5 ms, copy at 10 ms. The
    frame that draws the page has its vsync at `vsync_ns`, 2.0 ms, starts at
    `frame_ns`, 2.2 ms, and the page is drawn at 3.0 ms. KOReader's
    preparation is its CPU drawing, and it has no frame. For WebView,
    `running` gives the (vsync, start) of an animation frame that was running
    when preparation ended."""
    row = sample(number, engine=engine, id=f"measured-run/{number}", sequence=number,
                 preparation_event_id=f"measured-run/{number}",
                 preparation_operation="page_turn", engine_start_ns=1_100_000,
                 operation_returned_ns=1_200_000, preparation_ns=1_500_000,
                 engine_ready_ns=1_600_000, preparation_scope=SCOPES[engine],
                 drawn_ns=1_500_000 if engine == "koreader" else 3_000_000,
                 drawn_scope=DRAWN_SCOPES[engine],
                 phase_clock=dict(CLOCKS[engine]), end_ns=10_000_000)
    row.update(changes)
    unit, scale = {"bookfin": ("us", 1000), "webview": ("ms", 1_000_000)}.get(engine, (None, None))
    if unit:
        for field in ("start", "engine_start", "operation_returned", "preparation", "drawn"):
            source = f"{field}_source_{unit}"
            if (field not in ("start", "drawn") or engine == "bookfin") and source not in changes \
                    and type(row.get(f"{field}_ns")) is int:
                row[source] = row[f"{field}_ns"] / scale
    if engine == "bookfin" and "drawn_frame" not in changes and type(row.get("drawn_ns")) is int:
        row["drawn_frame"] = {"number": 9, "vsyncStart_us": vsync_ns // 1000, "buildStart_us": frame_ns // 1000,
                              "rasterFinish_us": row["drawn_ns"] // 1000}
    if engine == "webview":
        times = {"frame_vsync": vsync_ns, "frame_start": frame_ns,
                 "running_frame_vsync": running and running[0], "running_frame_start": running and running[1]}
        for field, value in times.items():
            row.setdefault(f"{field}_ns", value)
            if f"{field}_source_ms" not in changes:
                value = row[f"{field}_ns"]
                row[f"{field}_source_ms"] = value / 1_000_000 if type(value) is int else None
    return row


def interval(rows, name="prepared_page"):
    return summarize(rows).get("intervals", {}).get(name, {})


def cells(rows, name="prepared_page"):
    return interval(rows, name).get("cells", [])


class PreparedPageIntervalTest(unittest.TestCase):
    def test_a_median_halfway_between_two_tenths_rounds_up_in_the_published_table(self):
        # 35.8 and 35.9 ms have the exact median 35.85 ms, which rounds to 35.9.
        rows = [prepared(number, engine="webview", preparation_ns=1_100_000 + duration,
                         engine_ready_ns=1_200_000 + duration, frame_ns=40_000_000, drawn_ns=41_000_000,
                         end_ns=50_000_000)
                for number, duration in enumerate((35_800_000, 35_900_000))]
        summary = summarize(rows)
        self.assertIn("| WebView | Page turn | 35.9 / 35.9 (2) |", book_table(summary, PREPARED))
        self.assertEqual(_ms(summary["intervals"]["prepared_page"]["cells"][0]["mean_ms"]), "35.9")

    def test_every_engine_is_timed_from_its_own_entry_to_its_prepared_page(self):
        for engine in SCOPES:
            with self.subTest(engine=engine):
                found = cells([prepared(engine=engine)])
                self.assertEqual(len(found), 1)
                self.assertAlmostEqual(found[0]["mean_ms"], .4)
                self.assertEqual(found[0]["scope"], SCOPES[engine])

    def test_shell_dispatch_delay_before_engine_entry_is_not_engine_time(self):
        late_entry = prepared(engine="webview", engine_start_ns=1_150_000)
        self.assertAlmostEqual(cells([late_entry])[0]["mean_ms"], .35)

    def test_delaying_the_window_copy_does_not_move_any_engine_interval(self):
        for engine in SCOPES:
            with self.subTest(engine=engine):
                early = prepared(engine=engine)
                late = prepared(engine=engine, end_ns=90_000_000)
                for name in ("drawn_page", "prepared_page", "koreader_before_draw"):
                    self.assertEqual(interval([early], name), interval([late], name))
                self.assertNotEqual(summarize([early])["cells"], summarize([late])["cells"])

    def test_koreader_also_reports_its_layout_before_cpu_drawing(self):
        row = prepared(engine="koreader", operation_returned_ns=1_300_000)
        found = cells([row], "koreader_before_draw")
        self.assertEqual(len(found), 1)
        self.assertAlmostEqual(found[0]["mean_ms"], .2)
        self.assertEqual(found[0]["scope"], "koreader_layout_before_drawing")

    def test_only_koreader_has_a_before_draw_interval(self):
        rows = [prepared(0), prepared(1, engine="webview")]
        self.assertEqual(cells(rows, "koreader_before_draw"), [])
        self.assertEqual(interval(rows, "koreader_before_draw").get("excluded", []), [])

    def test_webview_samples_that_decoded_a_whole_section_are_not_page_samples(self):
        row = prepared(engine="webview",
                       preparation_scope="webview_layout_fonts_and_decoded_section_images")
        self.assertEqual(cells([row]), [])
        self.assertEqual(len(interval([row]).get("excluded", [])), 1)

    def test_stale_readiness_never_becomes_an_accepted_sample(self):
        for changes in ({"preparation_event_id": "previous-run/0"},
                        {"preparation_operation": "cached_reopen"}):
            with self.subTest(changes=changes):
                result = interval([prepared(**changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_missing_reversed_or_out_of_order_endpoints_are_excluded(self):
        for changes in ({"preparation_ns": None}, {"preparation_ns": 999_999},
                        {"preparation_ns": 11_000_000},
                        {"operation_returned_ns": 1_700_000},
                        {"engine_start_ns": None}, {"engine_start_ns": 900_000},
                        {"engine_start_ns": 1_250_000},
                        {"preparation_ns": True}, {"preparation_ns": float("nan")},
                        {"preparation_scope": SCOPES["webview"]},
                        {"phase_clock": {"source": "host_wall_time", "offset_ns": 0, "uncertainty_ns": 0}}):
            with self.subTest(changes=changes):
                result = interval([prepared(**changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_wrong_pixels_text_and_destination_exclude_every_interval_after_certification(self):
        for engine in SCOPES:
            for changes in ({"capture_sha256": "d" * 64}, {"visible_text": "wrong chapter"},
                            {"location": "epubcfi(/6/2!/4)"}):
                with self.subTest(engine=engine, changes=changes):
                    good = {**raw(engine=engine), "case": "target18"}
                    bad = {**raw(engine=engine, **changes), "case": "target18"}
                    references = {f"{engine}/prose/target18": {**reference()["bookfin/prose/target18"],
                                                               "engine": engine}}
                    certified = certify([{**prepared(engine=engine), **good},
                                         {**prepared(1, engine=engine), **bad}], references, "c" * 64)
                    names = ["drawn_page", "prepared_page"] + (["koreader_before_draw"] if engine == "koreader" else [])
                    for name in names:
                        result = interval(certified, name)
                        self.assertEqual(sum(cell["count"] for cell in result.get("cells", [])), 1)
                        self.assertIn("measured-run/1", [entry["id"] for entry in result.get("excluded", [])])

    def test_mean_weights_each_book_once_even_when_sample_counts_differ(self):
        rows = [prepared(preparation_ns=2_100_000, engine_ready_ns=2_200_000),
                prepared(1, book="long", preparation_ns=4_100_000, engine_ready_ns=4_200_000),
                prepared(2, book="long", preparation_ns=6_100_000, engine_ready_ns=6_200_000),
                prepared(3, book="illustrated", preparation_ns=10_100_000,
                         engine_ready_ns=10_200_000, end_ns=11_000_000)]
        means = interval(rows).get("equal_book_means", [])
        self.assertEqual(len(means), 1)
        self.assertAlmostEqual(means[0]["mean_ms"], (1 + 4 + 9) / 3)
        self.assertEqual(means[0]["book_count"], 3)

    def test_unavailable_preparation_is_not_filled_from_legacy_engine_ready(self):
        row = prepared()
        del row["preparation_ns"]
        self.assertEqual(cells([row]), [])
        self.assertEqual(len(summarize([row])["cells"]), 1)

    def test_engine_clocks_convert_raw_events_without_using_bridge_receipt_time(self):
        for engine in ("webview", "koreader"):
            with self.subTest(engine=engine):
                clock = {**CLOCKS[engine], "offset_ns": 1_000_000 if engine == "webview" else 0}
                row = prepared(engine=engine, phase_clock=clock)
                if engine == "webview":
                    for field in ("engine_start", "operation_returned", "preparation"):
                        row[f"{field}_source_ms"] = (row[f"{field}_ns"] - 1_000_000) / 1_000_000
                self.assertEqual(len(cells([row])), 1)

    def test_wrong_conversion_and_missing_source_timestamps_are_excluded(self):
        for engine, changes in (("bookfin", {"preparation_source_us": 1501}),
                                ("bookfin", {"preparation_source_us": None}),
                                ("bookfin", {"operation_returned_source_us": float("inf")}),
                                ("bookfin", {"start_source_us": 999}),
                                ("bookfin", {"engine_start_source_us": 1099}),
                                ("webview", {"engine_start_source_ms": 1.2}),
                                ("webview", {"engine_start_source_ms": None})):
            with self.subTest(engine=engine, changes=changes):
                result = interval([prepared(engine=engine, **changes)])
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)

    def test_webview_clock_must_state_its_observed_timer_resolution(self):
        clock = dict(CLOCKS["webview"])
        del clock["observed_resolution_ns"]
        self.assertEqual(cells([prepared(engine="webview", phase_clock=clock)]), [])

    def test_summary_does_not_rewrite_retained_raw_phase_timestamps(self):
        rows = [prepared(), prepared(1, engine="koreader")]
        original = copy.deepcopy(rows)
        summarize(rows)
        self.assertEqual(rows, original)


class DrawnPageIntervalTest(unittest.TestCase):
    def test_every_engine_is_timed_from_its_own_entry_through_its_drawing_without_the_wait_for_a_frame(self):
        # Entry 1.1 ms, preparation 1.5 ms, frame start 2.0 ms, drawn 3.0 ms:
        # 0.4 ms of preparation plus 1.0 ms of frame work.
        for engine, expected in (("bookfin", 1.4), ("webview", 1.4), ("koreader", .4)):
            with self.subTest(engine=engine):
                found = cells([prepared(engine=engine)], "drawn_page")
                self.assertEqual(len(found), 1)
                self.assertAlmostEqual(found[0]["mean_ms"], expected)
                self.assertEqual(found[0]["scope"], DRAWN_SCOPES[engine])

    def test_a_flutter_frame_rasterized_before_the_shell_saw_preparation_still_counts(self):
        row = prepared(drawn_ns=1_400_000, vsync_ns=1_250_000, frame_ns=1_300_000)
        self.assertAlmostEqual(cells([row], "drawn_page")[0]["mean_ms"], .3)

    def test_a_later_vsync_does_not_change_the_drawn_page(self):
        for engine in ("bookfin", "webview"):
            with self.subTest(engine=engine):
                prompt = prepared(engine=engine)
                late = prepared(engine=engine, vsync_ns=12_000_000, frame_ns=12_200_000, drawn_ns=13_000_000,
                                end_ns=20_000_000)
                self.assertAlmostEqual(cells([late], "drawn_page")[0]["mean_ms"],
                                       cells([prompt], "drawn_page")[0]["mean_ms"])

    def test_a_frame_that_began_before_preparation_ended_is_not_counted_twice(self):
        # Flutter can finish preparation between the start of a frame and its paint.
        row = prepared(vsync_ns=1_250_000, frame_ns=1_300_000)
        self.assertAlmostEqual(cells([row], "drawn_page")[0]["mean_ms"], 1.9)

    def test_a_frame_that_starts_late_after_its_vsync_keeps_that_delay(self):
        # Only the wait until the vsync at 2.0 ms is idle; 2.0 to 5.0 ms is thread time.
        for engine in ("bookfin", "webview"):
            with self.subTest(engine=engine):
                row = prepared(engine=engine, vsync_ns=2_000_000, frame_ns=5_000_000, drawn_ns=6_000_000)
                self.assertAlmostEqual(cells([row], "drawn_page")[0]["mean_ms"], 4.4)

    def test_a_webview_preparation_that_ends_inside_a_running_frame_subtracts_nothing(self):
        # The frame running at 1.3 ms draws the page; Android answers at 18.0 ms.
        row = prepared(engine="webview", running=(1_300_000, 1_350_000), vsync_ns=17_000_000,
                       frame_ns=17_200_000, drawn_ns=18_000_000, end_ns=20_000_000)
        self.assertAlmostEqual(cells([row], "drawn_page")[0]["mean_ms"], 16.9)

    def test_the_drawn_page_cells_name_the_wait_that_they_leave_out(self):
        self.assertEqual(cells([prepared()], "drawn_page")[0]["boundary"],
                         "engine_start_ns_to_drawn_ns_less_wait_until_drawing_frame_vsync")

    def test_samples_without_a_drawn_endpoint_stay_out_of_the_drawn_interval_only(self):
        row = prepared(engine="webview")
        del row["drawn_ns"]
        del row["drawn_scope"]
        self.assertEqual(cells([row], "drawn_page"), [])
        self.assertEqual(len(interval([row], "drawn_page")["excluded"]), 1)
        self.assertEqual(len(cells([row])), 1)

    def test_impossible_or_mislabeled_drawing_endpoints_are_excluded(self):
        for engine, changes in (("bookfin", {"drawn_ns": 1_100_000}),
                                ("bookfin", {"drawn_ns": 11_000_000}),
                                ("bookfin", {"drawn_source_us": 3001}),
                                ("bookfin", {"drawn_source_us": None}),
                                ("bookfin", {"drawn_frame": None}),
                                ("bookfin", {"drawn_frame": {"number": 9, "buildStart_us": 2200, "rasterFinish_us": 3000}}),
                                ("bookfin", {"drawn_frame": {"number": 9, "vsyncStart_us": 2300, "buildStart_us": 2200, "rasterFinish_us": 3000}}),
                                ("webview", {"frame_vsync_ns": None}),
                                ("webview", {"frame_vsync_source_ms": 2.1}),
                                ("webview", {"frame_vsync_ns": 2_300_000, "frame_vsync_source_ms": 2.3}),
                                ("webview", {"running_frame_vsync_ns": 1_600_000, "running_frame_vsync_source_ms": 1.6,
                                             "running_frame_start_ns": 1_400_000, "running_frame_start_source_ms": 1.4}),
                                ("webview", {"running_frame_vsync_ns": 1_300_000, "running_frame_vsync_source_ms": 1.3,
                                             "running_frame_start_ns": 1_600_000, "running_frame_start_source_ms": 1.6}),
                                ("webview", {"running_frame_vsync_ns": 1_300_000, "running_frame_vsync_source_ms": 1.4,
                                             "running_frame_start_ns": 1_350_000, "running_frame_start_source_ms": 1.35}),
                                ("bookfin", {"drawn_frame": {"number": 9, "vsyncStart_us": 2000, "buildStart_us": 3500, "rasterFinish_us": 3000}}),
                                ("bookfin", {"drawn_frame": {"number": 9, "vsyncStart_us": 900, "buildStart_us": 1000, "rasterFinish_us": 3000}}),
                                ("bookfin", {"drawn_frame": {"number": 9, "vsyncStart_us": 2000, "buildStart_us": 2200, "rasterFinish_us": 2900}}),
                                ("webview", {"frame_start_ns": None}),
                                ("webview", {"frame_start_ns": 1_400_000, "frame_start_source_ms": 1.4}),
                                ("webview", {"frame_start_ns": 3_500_000, "frame_start_source_ms": 3.5}),
                                ("webview", {"frame_start_source_ms": 2.1}),
                                ("webview", {"drawn_ns": 1_550_000}),
                                ("webview", {"drawn_scope": DRAWN_SCOPES["bookfin"]}),
                                ("koreader", {"drawn_ns": 1_600_000}),
                                ("koreader", {"drawn_ns": None})):
            with self.subTest(engine=engine, changes=changes):
                result = interval([prepared(engine=engine, **changes)], "drawn_page")
                self.assertEqual(result.get("cells", []), [])
                self.assertEqual(len(result.get("excluded", [])), 1)


if __name__ == "__main__":
    unittest.main()
