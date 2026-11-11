import json
import math
import re
import statistics
from collections import defaultdict


ENGINES = ("bookfin", "webview", "koreader")
OPERATIONS = ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change")
BOUNDARY = "request_to_reference_window_copy"


def summarize(rows):
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
        reason = _invalid(row)
        if reason:
            excluded.append({"id": identity, "reason": reason})
        else:
            grouped[(row["engine"], row["book"], row["operation"])].append(row)
    cells = []
    for (engine, book, operation), samples in sorted(grouped.items()):
        durations = sorted((row["end_ns"] - row["start_ns"]) / 1000000 for row in samples)
        cells.append({
            "engine": engine, "book": book, "operation": operation,
            "boundary": BOUNDARY, "count": len(samples),
            "rounds": len({row["round"] for row in samples}),
            "median_ms": statistics.median(durations),
            "p90_ms": durations[math.ceil(len(durations) * .9) - 1],
        })
    complete = len(cells) == len(ENGINES) * 3 * len(OPERATIONS) and all(
        cell["count"] >= (10 if cell["operation"] == "fresh_open" else 30)
        and cell["rounds"] >= 10 for cell in cells
    )
    return {"cells": cells, "excluded": excluded, "complete": complete}


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
