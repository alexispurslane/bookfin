import json
import math
import re
import statistics
from collections import defaultdict


ENGINES = ("bookfin", "webview", "koreader")
OPERATIONS = ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change")
BOUNDARY = "request_to_reference_window_copy"
PREPARATION_SCOPES = {
    "bookfin": "flutter_picture_and_decoded_page_images",
    "webview": "webview_layout_fonts_and_decoded_section_images",
    "koreader": "koreader_drawn_page_bitmap",
}
PHASE_CLOCKS = {"bookfin": "dart_timeline_us", "webview": "web_performance_ms",
                "koreader": "android_boottime_ns"}


def summarize(rows):
    result = _summarize(rows, "end_ns")
    result["milestones"] = {
        name: _summarize(rows, endpoint)
        for name, endpoint in (("operation_returned", "operation_returned_ns"),
                               ("preparation", "preparation_ns"))
    }
    return result


def _summarize(rows, endpoint):
    grouped = defaultdict(list)
    excluded = []
    seen = set()
    for row in rows:
        identity = row.get("id")
        if not identity:
            raise ValueError("sample has no id")
        if identity in seen:
            raise ValueError(f"duplicate sample id: {identity}")
        seen.add(identity)
        reason = _invalid(row) or (_invalid_preparation(row) if endpoint != "end_ns" else None)
        if reason:
            excluded.append({"id": identity, "reason": reason})
        else:
            grouped[(row["engine"], row["book"], row["operation"])].append(row)
    cells = []
    for (engine, book, operation), samples in sorted(grouped.items()):
        durations = sorted((row[endpoint] - row["start_ns"]) / 1000000 for row in samples)
        cells.append({
            "engine": engine, "book": book, "operation": operation,
            "boundary": BOUNDARY if endpoint == "end_ns" else endpoint,
            "scope": (BOUNDARY if endpoint == "end_ns" else
                      PREPARATION_SCOPES[engine] if endpoint == "preparation_ns" else
                      f"{engine}_operation_returned_before_resource_or_bitmap_preparation"),
            "count": len(samples),
            "rounds": len({row["round"] for row in samples}),
            "mean_ms": statistics.mean(durations),
            "median_ms": statistics.median(durations),
            "p90_ms": durations[math.ceil(len(durations) * .9) - 1],
        })
    complete = len(cells) == len(ENGINES) * 3 * len(OPERATIONS) and all(
        cell["count"] >= (10 if cell["operation"] == "fresh_open" else 30)
        and cell["rounds"] >= 10 for cell in cells
    )
    means = []
    for engine in ENGINES:
        for operation in OPERATIONS:
            books = [cell for cell in cells if cell["engine"] == engine and cell["operation"] == operation]
            if len(books) == 3:
                means.append({"engine": engine, "operation": operation, "book_count": 3,
                              "scope": books[0]["scope"],
                              "mean_ms": statistics.mean(cell["mean_ms"] for cell in books)})
    return {"cells": cells, "equal_book_means": means, "excluded": excluded, "complete": complete}


def _invalid_preparation(row):
    if row.get("preparation_event_id") != row["id"] or row.get("preparation_operation") != row["operation"]:
        return "stale or missing preparation event"
    if row.get("preparation_scope") != PREPARATION_SCOPES[row["engine"]]:
        return "wrong engine preparation scope"
    clock = row.get("phase_clock")
    if not isinstance(clock, dict) or clock.get("source") != PHASE_CLOCKS[row["engine"]]:
        return "missing or invalid phase clock"
    if any(type(clock.get(field)) is not int for field in ("offset_ns", "uncertainty_ns")) or clock["uncertainty_ns"] < 0:
        return "missing or invalid clock conversion"
    fields = ("start_ns", "operation_returned_ns", "preparation_ns", "engine_ready_ns", "end_ns")
    times = [row.get(field) for field in fields]
    if any(type(value) is not int for value in times) or times != sorted(times) or times[2] <= times[0]:
        return "missing, reversed, or out-of-order preparation endpoints"
    if row["engine"] != "koreader":
        unit, multiplier = ("us", 1000) if row["engine"] == "bookfin" else ("ms", 1_000_000)
        fields = ["operation_returned", "preparation"]
        if row["engine"] == "bookfin":
            fields.append("start")
        for field in fields:
            source = row.get(f"{field}_source_{unit}")
            if type(source) not in (int, float) or not math.isfinite(source):
                return "missing or invalid source timestamp"
            if abs(source * multiplier + clock["offset_ns"] - row[f"{field}_ns"]) > 1:
                return "source timestamp conversion mismatch"
    elif clock["offset_ns"] != 0 or clock["uncertainty_ns"] != 0:
        return "CLOCK_BOOTTIME needs no conversion"
    return None


def _invalid(row):
    if row.get("measured") is False:
        return "preparation (not a timed sample)"
    if row.get("warmup"):
        return "warmup"
    if row.get("error"):
        return f"engine error: {row['error']}"
    if type(row.get("round")) is not int or row["round"] < 0:
        return "missing or invalid round"
    if row.get("engine") not in ENGINES or row.get("book") not in ("prose", "long", "illustrated"):
        return "unknown engine or book"
    if row.get("operation") not in OPERATIONS:
        return "unknown operation"
    expected_cache = "fresh_document" if row["operation"] == "fresh_open" else "warm_document"
    if row.get("cache") != expected_cache:
        return "cache boundary mismatch"
    if row.get("boundary") != BOUNDARY or row.get("clock") != "android_elapsed_realtime_ns":
        return "completion boundary or clock mismatch"
    start, end = row.get("start_ns"), row.get("end_ns")
    if type(start) is not int or type(end) is not int or start < 0 or end <= start:
        return "missing or invalid timestamps"
    if not row.get("expected") or row.get("expected") != row.get("actual"):
        return "wrong destination"
    if not isinstance(row.get("text"), str) or not row["text"].strip():
        return "blank content"
    if row.get("window_copy_verified") is not True or row.get("content_verified") is not True:
        return "unverified content or window copy"
    if not row.get("reference_run_id") or row.get("reference_run_id") == row.get("run_id"):
        return "missing independent reference run"
    if not re.fullmatch(r"[0-9a-f]{64}", row.get("reference_manifest_sha256") or ""):
        return "missing reference manifest provenance"
    capture = row.get("capture_sha256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", capture) or capture != row.get("reference_sha256"):
        return "unverified or stale capture"
    return None


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("samples")
    arguments = parser.parse_args()
    with open(arguments.samples) as source:
        print(json.dumps(summarize([json.loads(line) for line in source if line.strip()]), indent=2))
