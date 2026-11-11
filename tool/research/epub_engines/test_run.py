import json
from pathlib import Path
import tempfile
import time
import unittest

from run import measure_quietly, quiet_host, sampled


def loads(*values):
    """A one-minute host load that reads the given values in turn."""
    readings = iter(values)
    return lambda: next(readings)


class QuietHostTest(unittest.TestCase):
    def test_a_job_starts_only_after_the_host_load_falls_under_the_limit(self):
        slept = []
        self.assertEqual(quiet_host(loads(12.0, 9.5, 5.0), slept.append, limit=8, checks=10), 5.0)
        self.assertEqual(len(slept), 2)

    def test_a_host_that_stays_busy_stops_the_run_instead_of_measuring(self):
        with self.assertRaises(RuntimeError):
            quiet_host(loads(*[12.0] * 3), lambda seconds: None, limit=8, checks=3)


class SampledTest(unittest.TestCase):
    def test_a_load_spike_during_a_job_counts_even_if_the_load_falls_before_it_ends(self):
        readings = iter([3.0, 13.0] + [4.0] * 100)
        result, peak = sampled(lambda: time.sleep(0.05) or "done", lambda: next(readings), interval=0.01)
        self.assertEqual((result, peak), ("done", 13.0))


class MeasureQuietlyTest(unittest.TestCase):
    def test_a_job_measured_while_the_host_was_busy_is_set_aside_and_measured_again(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            peaks = iter((14.0, 6.0))

            def attempt():
                (output / "run-a").mkdir()
                (output / "run-a" / "0.json").write_text("{}")
                (output / "run-a-instrumentation.txt").write_text("OK (1 test)")
                return next(peaks)

            measure_quietly("run-a", attempt, loads(5.0, 5.0), lambda seconds: None, output, limit=8)
            records = [json.loads(line) for line in (output / "host-load.jsonl").read_text().splitlines()]
            self.assertEqual([(record["attempt"], record["peak_load"], record["accepted"]) for record in records],
                             [(1, 14.0, False), (2, 6.0, True)])
            self.assertTrue((output / "rejected-load" / "run-a-attempt-1" / "0.json").exists())
            self.assertTrue((output / "rejected-load" / "run-a-attempt-1-instrumentation.txt").exists())
            self.assertTrue((output / "run-a" / "0.json").exists())

    def test_a_job_that_never_runs_on_a_quiet_host_stops_the_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)

            def attempt():
                (output / "run-a").mkdir()
                return 14.0

            with self.assertRaises(RuntimeError):
                measure_quietly("run-a", attempt, loads(*[5.0] * 3), lambda seconds: None, output, limit=8, attempts=3)
            self.assertFalse((output / "run-a").exists())


if __name__ == "__main__":
    unittest.main()
