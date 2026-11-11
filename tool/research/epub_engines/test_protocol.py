import collections
import unittest

from protocol import BOOKS, ENGINES, schedule


class ScheduleTest(unittest.TestCase):
    def test_every_book_and_engine_gets_twelve_independent_process_runs(self):
        counts = collections.Counter((job["book"], job["engine"]) for job in schedule())
        self.assertEqual(counts, {(book, engine): 12 for book in BOOKS for engine in ENGINES})

    def test_every_engine_has_each_order_position_four_times_for_each_book(self):
        counts = collections.Counter((job["book"], job["engine"], job["engine_order"]) for job in schedule())
        self.assertEqual(counts, {(book, engine, position): 4
                                 for book in BOOKS for engine in ENGINES for position in range(3)})

    def test_rejects_a_round_count_that_cannot_balance_engine_order(self):
        for rounds in (0, 1, 10, -3):
            with self.subTest(rounds=rounds), self.assertRaises(ValueError):
                schedule(rounds)

    def test_every_run_has_a_unique_reproducible_id(self):
        jobs = schedule()
        self.assertEqual(len(jobs), 108)
        self.assertEqual(len({job["run_id"] for job in jobs}), 108)
        self.assertEqual(jobs, schedule())


if __name__ == "__main__":
    unittest.main()
