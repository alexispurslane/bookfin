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
    "webview": "webview_layout_fonts_and_decoded_page_images",
    "koreader": "koreader_drawn_page_bitmap",
}
DRAWN_SCOPES = {
    "bookfin": "flutter_raster_finish_of_first_frame_with_page",
    "webview": "webview_visual_state_callback_after_preparation",
    "koreader": "koreader_cpu_drawn_page_bitmap",
}
PHASE_CLOCKS = {"bookfin": "dart_timeline_us", "webview": "web_performance_ms",
                "koreader": "android_boottime_ns"}
# Each interval starts when the engine's own code receives the request. The
# drawn page ends when the engine has drawn the requested page: on the GPU
# for Bookfin and WebView, on the CPU for KOReader. It leaves out the idle
# wait from the end of preparation to the start of the frame that draws the
# page, which only frame-based engines have. The prepared page ends before
# any GPU rasterization or composition.
INTERVALS = {
    "drawn_page": {"start": "engine_start_ns", "end": "drawn_ns",
                   "engines": ENGINES, "scopes": DRAWN_SCOPES},
    "prepared_page": {"start": "engine_start_ns", "end": "preparation_ns",
                      "engines": ENGINES, "scopes": PREPARATION_SCOPES},
    "koreader_before_draw": {"start": "engine_start_ns", "end": "operation_returned_ns",
                             "engines": ("koreader",),
                             "scopes": {"koreader": "koreader_layout_before_drawing"}},
}
PHASE_FIELDS = ("start_ns", "engine_start_ns", "operation_returned_ns", "preparation_ns",
                "engine_ready_ns", "end_ns")


def summarize(rows):
    result = _summarize(rows, "start_ns", "end_ns", ENGINES, None)
    result["intervals"] = {
        name: _summarize(rows, spec["start"], spec["end"], spec["engines"], spec["scopes"])
        for name, spec in INTERVALS.items()
    }
    return result


def _summarize(rows, start, end, engines, scopes):
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
        if scopes is not None and row.get("engine") not in engines:
            continue
        reason = (_invalid(row) or (_invalid_phases(row) if scopes is not None else None)
                  or (_invalid_drawing(row) if end == "drawn_ns" else None))
        if reason:
            excluded.append({"id": identity, "reason": reason})
        else:
            grouped[(row["engine"], row["book"], row["operation"])].append(row)
    cells = []
    for (engine, book, operation), samples in sorted(grouped.items()):
        idle = frame_wait if end == "drawn_ns" else (lambda row: 0)
        durations = sorted((row[end] - row[start] - idle(row)) / 1000000 for row in samples)
        cells.append({
            "engine": engine, "book": book, "operation": operation,
            "boundary": BOUNDARY if scopes is None else f"{start}_to_{end}",
            "scope": BOUNDARY if scopes is None else scopes[engine],
            "count": len(samples),
            "rounds": len({row["round"] for row in samples}),
            "mean_ms": statistics.mean(durations),
            "median_ms": statistics.median(durations),
            "p90_ms": durations[math.ceil(len(durations) * .9) - 1],
        })
    complete = len(cells) == len(engines) * 3 * len(OPERATIONS) and all(
        cell["count"] >= (10 if cell["operation"] == "fresh_open" else 30)
        and cell["rounds"] >= 10 for cell in cells
    )
    means = []
    for engine in engines:
        for operation in OPERATIONS:
            books = [cell for cell in cells if cell["engine"] == engine and cell["operation"] == operation]
            if len(books) == 3:
                means.append({"engine": engine, "operation": operation, "book_count": 3,
                              "scope": books[0]["scope"],
                              "mean_ms": statistics.mean(cell["mean_ms"] for cell in books)})
    return {"cells": cells, "equal_book_means": means, "excluded": excluded, "complete": complete}


def _invalid_phases(row):
    if row.get("preparation_event_id") != row["id"] or row.get("preparation_operation") != row["operation"]:
        return "stale or missing preparation event"
    if row.get("preparation_scope") != PREPARATION_SCOPES[row["engine"]]:
        return "wrong engine preparation scope"
    clock = row.get("phase_clock")
    if not isinstance(clock, dict) or clock.get("source") != PHASE_CLOCKS[row["engine"]]:
        return "missing or invalid phase clock"
    required = ["offset_ns", "uncertainty_ns"] + (["observed_resolution_ns"] if row["engine"] == "webview" else [])
    if any(type(clock.get(field)) is not int for field in required) or any(clock[field] < 0 for field in required[1:]):
        return "missing or invalid clock conversion"
    times = [row.get(field) for field in PHASE_FIELDS]
    if any(type(value) is not int for value in times) or times != sorted(times) or times[3] <= times[1]:
        return "missing, reversed, or out-of-order phase endpoints"
    if row["engine"] != "koreader":
        unit, multiplier = ("us", 1000) if row["engine"] == "bookfin" else ("ms", 1_000_000)
        fields = ["engine_start", "operation_returned", "preparation"]
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


def frame_wait(row):
    """Nanoseconds from the end of preparation until the frame that draws the
    page starts. Zero when that frame began before preparation ended, as a
    Flutter frame can: preparation then ends inside the frame's work."""
    if row["engine"] == "bookfin":
        frame = row["drawn_frame"]["buildStart_us"] * 1000 + row["phase_clock"]["offset_ns"]
    elif row["engine"] == "webview":
        frame = row["frame_start_ns"]
    else:
        return 0
    return max(0, frame - row["preparation_ns"])


def _invalid_drawing(row):
    engine = row["engine"]
    if row.get("drawn_scope") != DRAWN_SCOPES[engine]:
        return "missing or wrong drawing endpoint"
    drawn = row.get("drawn_ns")
    if type(drawn) is not int or not row["engine_start_ns"] < drawn <= row["end_ns"]:
        return "drawing endpoint outside the engine interval"
    if engine == "bookfin":
        source = row.get("drawn_source_us")
        if type(source) not in (int, float) or not math.isfinite(source) \
                or abs(source * 1000 + row["phase_clock"]["offset_ns"] - drawn) > 1:
            return "raster finish conversion mismatch"
        frame = row.get("drawn_frame")
        if not isinstance(frame, dict) or any(type(frame.get(phase)) is not int
                                              for phase in ("buildStart_us", "rasterFinish_us")):
            return "missing drawing frame timing"
        if frame["rasterFinish_us"] != source \
                or not row["engine_start_source_us"] < frame["buildStart_us"] <= frame["rasterFinish_us"]:
            return "drawing frame does not hold the requested page"
    elif engine == "webview" and drawn < row["engine_ready_ns"]:
        return "visual state callback before it was requested"
    elif engine == "webview":
        frame, source = row.get("frame_start_ns"), row.get("frame_start_source_ms")
        if type(frame) is not int or type(source) not in (int, float) or not math.isfinite(source) \
                or abs(source * 1_000_000 + row["phase_clock"]["offset_ns"] - frame) > 1:
            return "missing frame start or frame start conversion mismatch"
        if not row["preparation_ns"] <= frame < drawn:
            return "frame start outside preparation and drawing"
    elif engine == "koreader" and drawn != row["preparation_ns"]:
        return "KOReader draws its page in its preparation"
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
