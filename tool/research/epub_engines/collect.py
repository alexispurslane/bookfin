import argparse
import hashlib
import json
from pathlib import Path
import statistics

from results import summarize
from validation import certify


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", type=Path)
    parser.add_argument("references", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reference_bytes = args.references.read_bytes()
    references = json.loads(reference_bytes)
    rows = []
    jobs = json.loads((args.runs / "schedule.json").read_text())
    incomplete = []
    for job in jobs:
        directory = args.runs / job["run_id"]
        records = [json.loads(path.read_text()) for path in directory.glob("[0-9]*.json")]
        records.sort(key=lambda row: row["sequence"])
        assertion_log = args.runs / (job["run_id"] + "-instrumentation.txt")
        if len(records) != len(job["steps"]) or not (directory / "DONE").exists() or not assertion_log.exists() or "OK (1 test)" not in assertion_log.read_text():
            incomplete.append(job["run_id"])
        rows.extend(records)
    certified = certify(rows, references, hashlib.sha256(reference_bytes).hexdigest())
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "samples.jsonl").write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in certified))
    summary = summarize(certified)
    summary["incomplete_jobs"] = incomplete
    summary["complete"] = summary["complete"] and not incomplete
    summary["instrumentation_jobs"] = len(jobs) - len(incomplete)
    facts = []
    for engine in ("bookfin", "webview", "koreader"):
        for book in ("prose", "long", "illustrated"):
            selected = [row for row in certified if row["engine"] == engine and row["book"] == book]
            fresh = [row for row in selected if row["operation"] == "fresh_open"]
            verified_fresh = [row for row in fresh if row.get("content_verified") and row.get("window_copy_verified")]
            preparation = [row for row in selected if row["operation"] == "paginate"]
            measurements = [row for row in selected if row["measured"]]
            if not fresh:
                continue
            facts.append({"engine": engine, "book": book,
                          "independent_process_start_count": len({row["process_start_ns"] for row in fresh}),
                          "instrumented_process_to_shell_ready_median_ms": statistics.median((row["shell_ready_ns"] - row["process_start_ns"]) / 1e6 for row in fresh),
                          "instrumented_process_to_first_verified_copy_median_ms": statistics.median((row["end_ns"] - row["process_start_ns"]) / 1e6 for row in verified_fresh) if verified_fresh else None,
                          "fresh_open_whole_book_complete_count": sum(row["whole_book_paginated"] for row in fresh),
                          "preparation_whole_book_complete_count": sum(row["whole_book_paginated"] for row in preparation),
                          "preparation_engine_ready_median_ms": statistics.median((row["engine_ready_ns"] - row["start_ns"]) / 1e6 for row in preparation) if preparation else None,
                          "last_pixel_copy_median_ms": statistics.median(row["copy_duration_ns"] / 1e6 for row in measurements) if measurements else None,
                          "capture_attempts_max": max((row["capture_attempts"] for row in measurements), default=None)})
    summary["independent_processes_complete"] = len(facts) == 9 and all(fact["independent_process_start_count"] >= 10 for fact in facts)
    summary["complete"] = summary["complete"] and summary["independent_processes_complete"]
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (args.output / "facts.json").write_text(json.dumps(facts, indent=2) + "\n")
    print(json.dumps({"cells": len(summary["cells"]), "excluded": len(summary["excluded"]),
                      "complete": summary["complete"], "incomplete_jobs": incomplete}))


if __name__ == "__main__":
    main()
