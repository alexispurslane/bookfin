import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class PartialEvidenceTest(unittest.TestCase):
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
