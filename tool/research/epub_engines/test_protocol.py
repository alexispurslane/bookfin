import collections
import unittest

from protocol import BOOKS, ENGINES, schedule


def standard(jobs):
    return [job for job in jobs if "variant" not in job]


def prepared(jobs):
    return [job for job in jobs if job.get("variant") == "prepared_at_download"]


class ScheduleTest(unittest.TestCase):
    def test_every_book_and_engine_gets_twelve_independent_process_runs(self):
        counts = collections.Counter((job["book"], job["engine"]) for job in standard(schedule()))
        self.assertEqual(counts, {(book, engine): 12 for book in BOOKS for engine in ENGINES})

    def test_every_engine_has_each_order_position_four_times_for_each_book(self):
        counts = collections.Counter((job["book"], job["engine"], job["engine_order"]) for job in standard(schedule()))
        self.assertEqual(counts, {(book, engine, position): 4
                                 for book in BOOKS for engine in ENGINES for position in range(3)})

    def test_each_book_gets_twelve_bookfin_processes_whose_book_was_prepared_at_download(self):
        counts = collections.Counter((job["book"], job["engine"]) for job in prepared(schedule()))
        self.assertEqual(counts, {(book, "bookfin"): 12 for book in BOOKS})

    def test_a_process_prepared_at_download_runs_only_its_fresh_open(self):
        for job in prepared(schedule()):
            self.assertEqual(job["steps"], [{"operation": "fresh_open", "case": "target18", "measured": True}])

    def test_the_prepared_process_takes_each_place_among_a_books_four_processes_three_times(self):
        jobs = schedule()
        places = collections.Counter()
        for round_index in range(12):
            for book in BOOKS:
                group = [job for job in jobs if job["round"] == round_index and job["book"] == book]
                self.assertEqual(len(group), 4)
                places[(book, next(index for index, job in enumerate(group) if "variant" in job))] += 1
        self.assertEqual(places, {(book, place): 3 for book in BOOKS for place in range(4)})

    def test_the_standard_processes_keep_the_ids_and_order_of_the_earlier_runs(self):
        jobs = standard(schedule())
        self.assertEqual([job["run_id"] for job in jobs][:4],
                         ["round-00-prose-bookfin", "round-00-prose-webview",
                          "round-00-prose-koreader", "round-00-long-webview"])

    def test_rejects_a_round_count_that_cannot_balance_engine_order(self):
        for rounds in (0, 1, 10, -3):
            with self.subTest(rounds=rounds), self.assertRaises(ValueError):
                schedule(rounds)

    def test_every_run_has_a_unique_reproducible_id(self):
        jobs = schedule()
        self.assertEqual(len(jobs), 144)
        self.assertEqual(len({job["run_id"] for job in jobs}), 144)
        self.assertEqual(jobs, schedule())

    def test_each_process_runs_one_fresh_open_and_three_of_each_warm_operation(self):
        steps = standard(schedule())[0].get("steps", [])
        measured = collections.Counter(step["operation"] for step in steps if step["measured"])
        self.assertEqual(measured, {"fresh_open": 1, "cached_reopen": 3, "page_turn": 3,
                                    "chapter_crossing": 3, "font_change": 3})

    def test_each_crossing_starts_at_the_previous_sections_last_page(self):
        steps = standard(schedule())[0].get("steps", [])
        crossings = [index for index, step in enumerate(steps) if step["operation"] == "chapter_crossing"]
        self.assertEqual(len(crossings), 3)
        for index in crossings:
            self.assertEqual(steps[index-1]["operation"], "prepare_crossing")
            self.assertFalse(steps[index-1]["measured"])

    def test_font_changes_always_start_from_the_same_location_and_size(self):
        steps = standard(schedule())[0].get("steps", [])
        changes = [index for index, step in enumerate(steps) if step["operation"] == "font_change"]
        self.assertEqual(len(changes), 3)
        for index in changes:
            self.assertEqual(steps[index-1]["operation"], "prepare_target")

    def test_reopens_start_from_different_content_so_old_pixels_cannot_pass(self):
        steps = standard(schedule())[0]["steps"]
        for index, step in enumerate(steps):
            if step["operation"] == "cached_reopen":
                self.assertEqual(steps[index-1]["operation"], "prepare_reopen")
                self.assertNotEqual(steps[index-1]["case"], step["case"])


if __name__ == "__main__":
    unittest.main()
