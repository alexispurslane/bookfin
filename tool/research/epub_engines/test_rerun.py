"""The Bookfin rows that the November 12 rerun adds: a fresh open of a book
prepared at download, the preparation itself, and the kept page that a
cached reopen draws before the true page."""
import unittest

from tables import RERUN, rerun_table
from test_preparation import cells, interval, prepared


KEPT_SCOPE = "flutter_raster_finish_of_first_frame_with_kept_page"


def reopen(number=0, kept_ready_ns=1_300_000, vsync_ns=1_700_000, frame_ns=1_800_000,
           kept_drawn_ns=2_000_000, depicts=True, **changes):
    """A certified cached reopen whose kept page was ready at 1.3 ms, drew in
    a frame with its vsync at 1.7 ms and its raster finish at 2.0 ms. Entry
    is at 1.1 ms. The true page draws at 3.0 ms, as in `prepared`."""
    row = prepared(number, operation="cached_reopen", preparation_operation="cached_reopen", **changes)
    if kept_drawn_ns is not None:
        row.update({"kept_ready_ns": kept_ready_ns, "kept_ready_source_us": kept_ready_ns / 1000,
                    "kept_drawn_ns": kept_drawn_ns, "kept_drawn_source_us": kept_drawn_ns / 1000,
                    "kept_drawn_scope": KEPT_SCOPE, "kept_depicts_page": depicts,
                    "kept_drawn_frame": {"number": 7, "vsyncStart_us": vsync_ns // 1000,
                                         "buildStart_us": frame_ns // 1000,
                                         "rasterFinish_us": kept_drawn_ns // 1000}})
    else:
        row["kept_status"] = "no kept page"
    return row


def prepared_open(number=0, start_ns=200_000, end_ns=900_000, **changes):
    """A certified fresh open of a book that Bookfin prepared at download:
    the preparation ran from `start_ns` to `end_ns`, before engine entry at
    1.1 ms."""
    row = prepared(number, **{"operation": "fresh_open", "preparation_operation": "fresh_open",
                              "cache": "prepared_at_download", "variant": "prepared_at_download", **changes})
    row.update({"download_preparation_start_ns": start_ns, "download_preparation_end_ns": end_ns,
                "download_preparation_start_source_us": start_ns / 1000,
                "download_preparation_end_source_us": end_ns / 1000})
    return row


def cold_open(number=0, **changes):
    return prepared(number, **{"operation": "fresh_open", "preparation_operation": "fresh_open",
                               "cache": "fresh_document", **changes})


class FreshOpenPreparedAtDownloadTest(unittest.TestCase):
    def test_a_book_prepared_at_download_opens_in_a_cell_apart_from_the_cold_open(self):
        found = cells([cold_open(0), prepared_open(1)], "drawn_page")
        self.assertEqual(sorted(cell["operation"] for cell in found), ["fresh_open", "fresh_open_prepared"])

    def test_the_preparation_at_download_is_timed_from_its_call_to_its_return(self):
        found = cells([prepared_open(start_ns=200_000, end_ns=900_000)], "download_preparation")
        self.assertEqual(len(found), 1)
        self.assertAlmostEqual(found[0]["mean_ms"], .7)

    def test_only_processes_prepared_at_download_have_a_preparation_sample(self):
        result = interval([cold_open(0), prepare_free_reopen(1)], "download_preparation")
        self.assertEqual(result["cells"], [])

    def test_a_preparation_that_overlaps_the_open_is_excluded(self):
        result = interval([prepared_open(end_ns=1_200_000)], "download_preparation")
        self.assertEqual(result["cells"], [])
        self.assertEqual(len(result["excluded"]), 1)

    def test_a_prepared_open_claims_the_cache_state_of_a_prepared_book(self):
        self.assertEqual(cells([prepared_open(cache="fresh_document")], "drawn_page"), [])


def prepare_free_reopen(number):
    return reopen(number)


class KeptPageOfACachedReopenTest(unittest.TestCase):
    def test_the_kept_page_is_timed_to_its_raster_finish_without_the_wait_for_its_frame(self):
        # Entry 1.1 ms, kept page ready 1.3 ms, vsync 1.7 ms, raster finish
        # 2.0 ms: 0.2 ms before the wait and 0.3 ms after it.
        found = cells([reopen()], "kept_page")
        self.assertEqual(len(found), 1)
        self.assertAlmostEqual(found[0]["mean_ms"], .5)
        self.assertEqual(found[0]["scope"], KEPT_SCOPE)

    def test_the_true_page_of_the_same_reopen_stays_in_the_drawn_page(self):
        self.assertAlmostEqual(cells([reopen()], "drawn_page")[0]["mean_ms"], 1.4)

    def test_a_kept_frame_that_began_before_the_page_was_ready_subtracts_nothing(self):
        row = reopen(kept_ready_ns=1_800_000, vsync_ns=1_700_000, frame_ns=1_750_000)
        self.assertAlmostEqual(cells([row], "kept_page")[0]["mean_ms"], .9)

    def test_a_reopen_that_showed_no_kept_page_is_excluded_from_the_kept_page_with_its_reason(self):
        result = interval([reopen(kept_drawn_ns=None)], "kept_page")
        self.assertEqual(result["cells"], [])
        self.assertEqual(result["excluded"][0]["reason"], "no kept page drawn: no kept page")

    def test_a_kept_page_that_does_not_depict_the_true_page_is_excluded(self):
        result = interval([reopen(depicts=False)], "kept_page")
        self.assertEqual(result["cells"], [])

    def test_a_kept_page_drawn_after_the_true_page_is_excluded(self):
        result = interval([reopen(kept_drawn_ns=3_500_000)], "kept_page")
        self.assertEqual(result["cells"], [])

    def test_only_bookfin_cached_reopens_have_a_kept_page(self):
        rows = [reopen(0), prepared(1, operation="page_turn"), cold_open(2),
                prepared(3, engine="koreader", operation="cached_reopen", preparation_operation="cached_reopen")]
        self.assertEqual([(cell["engine"], cell["operation"]) for cell in cells(rows, "kept_page")],
                         [("bookfin", "cached_reopen")])


class RerunTableTest(unittest.TestCase):
    def test_the_rerun_table_names_every_bookfin_row_and_leaves_other_engines_out_of_them(self):
        rows = [cold_open(0), prepared_open(1), reopen(2),
                cold_open(3, engine="webview"), cold_open(4, engine="koreader")]
        for number, book in enumerate(("long", "illustrated")):
            rows += [cold_open(10 + number, book=book), prepared_open(20 + number, book=book),
                     reopen(30 + number, book=book), cold_open(40 + number, engine="webview", book=book),
                     cold_open(50 + number, engine="koreader", book=book)]
        from results import summarize
        table = rerun_table(summarize(rows), RERUN).splitlines()
        labels = [line.split(" | ")[0].lstrip("| ") for line in table[2:]]
        self.assertEqual(labels, ["Fresh open, no preparation", "Fresh open, prepared at download",
                                  "Preparation at download (background)", "Cached reopen, kept page",
                                  "Cached reopen, true page", "Page turn", "Chapter turn (visited)",
                                  "Size change"])
        prepared_row = table[3].split(" | ")
        self.assertNotEqual(prepared_row[1], "n/a")
        self.assertEqual(prepared_row[2:], ["n/a", "n/a |"])


if __name__ == "__main__":
    unittest.main()
