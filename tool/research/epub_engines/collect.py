import argparse
import hashlib
import json
from pathlib import Path
import statistics

from results import ENGINES, frame_wait, summarize
from validation import certify


def answered_after_a_later_vsync(row):
    """Whether Android answered a WebView page after a vsync that followed the
    start of the frame that drew the page: the page reached Android's drawing
    only at a later vsync. If preparation ended inside a running frame, the
    later vsync is the measured one of the first frame after preparation.
    Otherwise it is the first vsync after the drawing frame's start, which
    can come after the next vsync if the frame started late."""
    if row.get("running_frame_vsync_ns") is not None:
        return row["drawn_ns"] > row["frame_vsync_ns"]
    period = row["next_frame_vsync_ns"] - row["frame_vsync_ns"]
    later = row["frame_vsync_ns"] + period * (1 + max(0, row["frame_start_ns"] - row["frame_vsync_ns"]) // period)
    return row["drawn_ns"] > later


def accepted(row):
    """Whether a row is a measured page that matched its reference."""
    return row["measured"] and row.get("content_verified") and row.get("window_copy_verified") and not row.get("error")


def frame_counts(rows):
    """For each engine and action, how many frames ran inside preparation,
    how often WebView's preparation ended inside a running frame, and how
    often Android answered WebView after a later vsync."""
    entries = []
    for engine in ENGINES:
        for operation in dict.fromkeys(row["operation"] for row in rows):
            selected = [row for row in rows if row["engine"] == engine and row["operation"] == operation and accepted(row)]
            if not selected:
                continue
            counted = [row["frames_in_preparation"] for row in selected if type(row.get("frames_in_preparation")) is int]
            web = engine == "webview"
            entries.append({"engine": engine, "operation": operation, "samples": len(selected),
                            "frames_in_preparation_median": statistics.median(counted) if counted else None,
                            "frames_in_preparation_max": max(counted, default=None),
                            "preparation_in_running_frame":
                                sum(row.get("running_frame_vsync_ns") is not None for row in selected) if web else None,
                            "answered_after_later_vsync":
                                sum(map(answered_after_a_later_vsync, filter(answer_known, selected))) if web else None})
    return entries


def answer_known(row):
    """Whether a WebView row has the vsync times that date Android's answer."""
    return type(row.get("drawn_ns")) is int and type(row.get("frame_vsync_ns")) is int \
        and type(row.get("frame_start_ns")) is int and type(row.get("next_frame_vsync_ns")) is int \
        and row["next_frame_vsync_ns"] > row["frame_vsync_ns"]


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
    # A run with a host-load log keeps no row of a job that has no accepted
    # quiet-host measurement: such rows were timed while the host was busy.
    load_log = args.runs / "host-load.jsonl"
    quiet = {record["run_id"] for record in map(json.loads, load_log.read_text().splitlines())
             if record["accepted"]} if load_log.exists() else None
    for job in jobs:
        directory = args.runs / job["run_id"]
        records = [json.loads(path.read_text()) for path in directory.glob("[0-9]*.json")]
        records.sort(key=lambda row: row["sequence"])
        assertion_log = args.runs / (job["run_id"] + "-instrumentation.txt")
        if quiet is not None and job["run_id"] not in quiet:
            incomplete.append(job["run_id"])
            continue
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
            kept = [row for row in measurements if accepted(row)]
            entered = [row for row in kept if type(row.get("engine_start_ns")) is int]
            drawn = [row for row in kept if engine == "koreader" and type(row.get("redraw_duration_ns")) is int]
            painted = [row for row in kept if type(row.get("drawn_ns")) is int]
            frames = [row["drawn_frame"] for row in painted if engine == "bookfin" and isinstance(row.get("drawn_frame"), dict)]
            waited = [row for row in painted
                      if engine == "bookfin" and type((row.get("drawn_frame") or {}).get("vsyncStart_us")) is int
                      or engine == "webview" and type(row.get("frame_vsync_ns")) is int]
            answered = [row for row in painted if engine == "webview" and answer_known(row)]
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
                          "capture_attempts_max": max((row["capture_attempts"] for row in measurements), default=None),
                          "dispatch_to_engine_entry_median_ms": statistics.median((row["engine_start_ns"] - row["start_ns"]) / 1e6 for row in entered) if entered else None,
                          "koreader_draw_median_ms": statistics.median((row["preparation_ns"] - row["operation_returned_ns"]) / 1e6 for row in drawn) if drawn else None,
                          "koreader_redraw_median_ms": statistics.median(row["redraw_duration_ns"] / 1e6 for row in drawn) if drawn else None,
                          "drawn_after_preparation_median_ms": statistics.median((row["drawn_ns"] - row["preparation_ns"]) / 1e6 for row in painted) if painted else None,
                          "flutter_raster_median_ms": statistics.median((frame["rasterFinish_us"] - frame["rasterStart_us"]) / 1e3 for frame in frames) if frames else None,
                          "removed_frame_wait_median_ms": statistics.median(frame_wait(row) / 1e6 for row in waited) if waited else None,
                          "webview_answer_checked_count": len(answered) if answered else None,
                          "webview_answer_after_next_vsync_count": sum(map(answered_after_a_later_vsync, answered)) if answered else None,
                          "webview_preparation_in_running_frame_count":
                              sum(row.get("running_frame_vsync_ns") is not None for row in answered) if answered else None})
    summary["independent_processes_complete"] = len(facts) == 9 and all(fact["independent_process_start_count"] >= 10 for fact in facts)
    summary["complete"] = summary["complete"] and summary["independent_processes_complete"]
    for interval in summary["intervals"].values():
        interval["complete"] = interval["complete"] and not incomplete and summary["independent_processes_complete"]
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (args.output / "facts.json").write_text(json.dumps(facts, indent=2) + "\n")
    (args.output / "frames.json").write_text(json.dumps(frame_counts(certified), indent=2) + "\n")
    print(json.dumps({"cells": len(summary["cells"]), "excluded": len(summary["excluded"]),
                      "complete": summary["complete"], "incomplete_jobs": incomplete}))


if __name__ == "__main__":
    main()
