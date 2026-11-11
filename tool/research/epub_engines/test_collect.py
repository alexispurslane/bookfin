import json
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from test_validation import raw, reference


class PartialEvidenceTest(unittest.TestCase):
    def test_first_process_latency_uses_each_verified_completion_not_summed_medians(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs = root / "runs"
            runs.mkdir()
            references = root / "references.json"
            references.write_text(json.dumps(reference()))
            digest = hashlib.sha256(references.read_bytes()).hexdigest()
            jobs = []
            for number, (startup_ms, open_ms) in enumerate(((1, 100), (100, 1), (10, 10))):
                run = f"run-{number}"
                directory = runs / run
                directory.mkdir()
                process_start = number * 1_000_000_000
                start = process_start + startup_ms * 1_000_000
                end = start + open_ms * 1_000_000
                row = raw(id=run+"/0", run_id=run, sequence=0, operation="fresh_open", round=number,
                          measured=True, warmup=False, cache="fresh_document", boundary="request_to_reference_window_copy",
                          clock="android_elapsed_realtime_ns", start_ns=start, engine_ready_ns=end-500_000, end_ns=end,
                          process_start_ns=process_start, shell_ready_ns=start, whole_book_paginated=False,
                          copy_duration_ns=500_000, capture_attempts=1, reference_manifest_sha256=digest)
                (directory / "0.json").write_text(json.dumps(row))
                (directory / "DONE").touch()
                (runs / (run + "-instrumentation.txt")).write_text("OK (1 test)")
                jobs.append({"run_id": run, "steps": [{}]})
            (runs / "schedule.json").write_text(json.dumps(jobs))
            output = root / "output"
            completed = subprocess.run([sys.executable, str(Path(__file__).with_name("collect.py")),
                                        str(runs), str(references), "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            fact = json.loads((output / "facts.json").read_text())[0]
            self.assertEqual(fact.get("instrumented_process_to_first_verified_copy_median_ms"), 101)

    def test_failed_partial_workloads_remain_collectable_without_inventing_preparation_facts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs = root / "runs"
            job = runs / "failed-run"
            job.mkdir(parents=True)
            (runs / "schedule.json").write_text(json.dumps([{"run_id": "failed-run", "steps": [{}, {}]}]))
            row = {"id": "failed-run/0", "run_id": "failed-run", "sequence": 0, "engine": "webview",
                   "book": "prose", "operation": "fresh_open", "case": "target18", "round": 0,
                   "measured": True, "start_ns": 1000000, "engine_ready_ns": 2000000,
                   "end_ns": 3000000, "process_start_ns": 0, "shell_ready_ns": 500000,
                   "whole_book_paginated": False, "copy_duration_ns": 100000, "capture_attempts": 1,
                   "visible_text": "Actual partial content is retained for diagnosis"}
            (job / "0.json").write_text(json.dumps(row))
            references = root / "references.json"
            references.write_text("{}")
            output = root / "output"
            completed = subprocess.run([sys.executable, str(Path(__file__).with_name("collect.py")),
                                        str(runs), str(references), "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            summary = json.loads((output / "summary.json").read_text())
            self.assertFalse(summary["complete"])
            self.assertEqual(summary["incomplete_jobs"], ["failed-run"])
            self.assertEqual(len((output / "samples.jsonl").read_text().splitlines()), 1)
            self.assertIsNone(json.loads((output / "facts.json").read_text())[0]["preparation_engine_ready_median_ms"])
            self.assertIsNone(json.loads((output / "facts.json").read_text())[0]["instrumented_process_to_first_verified_copy_median_ms"])

    def test_engine_phase_facts_come_only_from_certified_samples(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs = root / "runs"
            runs.mkdir()
            references = root / "references.json"
            references.write_text(json.dumps({"koreader/prose/target18": {**reference()["bookfin/prose/target18"], "engine": "koreader"}}))
            digest = hashlib.sha256(references.read_bytes()).hexdigest()
            jobs = []
            # Two certified samples and one with wrong pixels. Certified draws
            # take 2 and 4 ms, repeat draws 1 and 3 ms, shell hops 0.2 and 0.4 ms.
            for number, (hop, draw, redraw, pixels) in enumerate(((.2, 2, 1, "a"), (.4, 4, 3, "a"), (9, 90, 90, "d"))):
                run = f"run-{number}"
                directory = runs / run
                directory.mkdir()
                start = 10_000_000_000 * (number + 1)
                entry = start + int(hop * 1e6)
                returned = entry + 5_000_000
                prepared = returned + draw * 1_000_000
                row = raw(engine="koreader", id=run + "/0", run_id=run, sequence=0, operation="fresh_open", round=number,
                          measured=True, warmup=False, cache="fresh_document", boundary="request_to_reference_window_copy",
                          clock="android_elapsed_realtime_ns", start_ns=start, engine_start_ns=entry,
                          operation_returned_ns=returned, preparation_ns=prepared, redraw_duration_ns=redraw * 1_000_000,
                          engine_ready_ns=prepared + 1, end_ns=prepared + 2, process_start_ns=start - 1, shell_ready_ns=start,
                          whole_book_paginated=True, copy_duration_ns=1, capture_attempts=1,
                          capture_sha256=pixels * 64, reference_manifest_sha256=digest)
                (directory / "0.json").write_text(json.dumps(row))
                (directory / "DONE").touch()
                (runs / (run + "-instrumentation.txt")).write_text("OK (1 test)")
                jobs.append({"run_id": run, "steps": [{}]})
            (runs / "schedule.json").write_text(json.dumps(jobs))
            output = root / "output"
            completed = subprocess.run([sys.executable, str(Path(__file__).with_name("collect.py")),
                                        str(runs), str(references), "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            fact = json.loads((output / "facts.json").read_text())[0]
            self.assertAlmostEqual(fact.get("dispatch_to_engine_entry_median_ms"), .3)
            self.assertAlmostEqual(fact.get("koreader_draw_median_ms"), 3)
            self.assertAlmostEqual(fact.get("koreader_redraw_median_ms"), 2)

    def test_drawing_facts_describe_the_wait_after_preparation_and_flutter_raster(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            runs = root / "runs"
            runs.mkdir()
            references = root / "references.json"
            references.write_text(json.dumps(reference()))
            digest = hashlib.sha256(references.read_bytes()).hexdigest()
            jobs = []
            # Drawn 10 and 30 ms after preparation; raster 2 and 6 ms.
            for number, (wait, raster) in enumerate(((10, 2), (30, 6))):
                run = f"run-{number}"
                directory = runs / run
                directory.mkdir()
                start = 10_000_000_000 * (number + 1)
                prepared = start + 5_000_000
                drawn = prepared + wait * 1_000_000
                row = raw(id=run + "/0", run_id=run, sequence=0, operation="fresh_open", round=number,
                          measured=True, warmup=False, cache="fresh_document", boundary="request_to_reference_window_copy",
                          clock="android_elapsed_realtime_ns", start_ns=start, engine_start_ns=start,
                          operation_returned_ns=prepared, preparation_ns=prepared, drawn_ns=drawn,
                          drawn_frame={"rasterStart_us": 1000, "rasterFinish_us": 1000 + raster * 1000},
                          engine_ready_ns=prepared + 1, end_ns=drawn + 1, process_start_ns=start - 1, shell_ready_ns=start,
                          whole_book_paginated=False, copy_duration_ns=1, capture_attempts=1,
                          reference_manifest_sha256=digest)
                (directory / "0.json").write_text(json.dumps(row))
                (directory / "DONE").touch()
                (runs / (run + "-instrumentation.txt")).write_text("OK (1 test)")
                jobs.append({"run_id": run, "steps": [{}]})
            (runs / "schedule.json").write_text(json.dumps(jobs))
            output = root / "output"
            completed = subprocess.run([sys.executable, str(Path(__file__).with_name("collect.py")),
                                        str(runs), str(references), "--output", str(output)], capture_output=True, text=True)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            fact = json.loads((output / "facts.json").read_text())[0]
            self.assertAlmostEqual(fact.get("drawn_after_preparation_median_ms"), 20)
            self.assertAlmostEqual(fact.get("flutter_raster_median_ms"), 4)
