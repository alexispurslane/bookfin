import json
import math
import re
from collections import defaultdict
from fractions import Fraction


ENGINES = ("bookfin", "webview", "koreader")
OPERATIONS = ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change")
# A Bookfin fresh open of a book that Bookfin prepared at download (boo-sy2d)
# is a cell of its own, apart from the cold fresh open.
PREPARED_AT_DOWNLOAD = "prepared_at_download"
PREPARED_OPEN = "fresh_open_prepared"
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
PHASE_FIELDS = ("start_ns", "engine_start_ns", "operation_returned_ns", "preparation_ns",
                "engine_ready_ns", "end_ns")


def summarize(rows):
    result = _summarize(rows, {"start": "start_ns", "end": "end_ns", "engines": ENGINES, "scopes": None})
    result["intervals"] = {name: _summarize(rows, spec) for name, spec in INTERVALS.items()}
    return result


def cell_operation(row):
    """The action of a row's cell: its operation, or the prepared fresh open."""
    if row.get("variant") == PREPARED_AT_DOWNLOAD and row.get("operation") == "fresh_open":
        return PREPARED_OPEN
    return row.get("operation")


def _summarize(rows, spec):
    start, end, engines, scopes = spec["start"], spec["end"], spec["engines"], spec["scopes"]
    less, check = spec.get("less", lambda row: 0), spec.get("check", lambda row: None)
    select, operations = spec.get("select", lambda row: True), spec.get("operations", OPERATIONS)
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
        if scopes is not None and row.get("engine") not in engines or not select(row):
            continue
        reason = _invalid(row) or (_invalid_phases(row) if scopes is not None else None) or check(row)
        if reason:
            excluded.append({"id": identity, "reason": reason})
        else:
            grouped[(row["engine"], row["book"], cell_operation(row))].append(row)
    cells = []
    exact_means = {}
    for (engine, book, operation), samples in sorted(grouped.items()):
        # Integer nanoseconds and exact fractions until the last step, so that
        # a value halfway between two tenths of a millisecond stays exact.
        durations = sorted(row[end] - row[start] - less(row) for row in samples)
        count = len(durations)
        exact_means[(engine, book, operation)] = Fraction(sum(durations), count)
        middle = (Fraction(durations[count // 2]) if count % 2
                  else Fraction(durations[count // 2 - 1] + durations[count // 2], 2))
        cells.append({
            "engine": engine, "book": book, "operation": operation,
            "boundary": BOUNDARY if scopes is None else spec.get("boundary", f"{start}_to_{end}"),
            "scope": BOUNDARY if scopes is None else scopes[engine],
            "count": count,
            "rounds": len({row["round"] for row in samples}),
            "mean_ms": _milliseconds(exact_means[(engine, book, operation)]),
            "median_ms": _milliseconds(middle),
            "p90_ms": _milliseconds(durations[math.ceil(count * Fraction(9, 10)) - 1]),
        })
    found = {(cell["engine"], cell["book"], cell["operation"]) for cell in cells}
    complete = all((engine, book, operation) in found for engine in engines
                   for book in ("prose", "long", "illustrated") for operation in operations) and all(
        cell["count"] >= (10 if cell["operation"].startswith("fresh_open") else 30)
        and cell["rounds"] >= 10 for cell in cells
    )
    means = []
    for engine in engines:
        for operation in OPERATIONS + (PREPARED_OPEN,):
            books = [cell for cell in cells if cell["engine"] == engine and cell["operation"] == operation]
            if len(books) == 3:
                means.append({"engine": engine, "operation": operation, "book_count": 3,
                              "scope": books[0]["scope"],
                              "mean_ms": _milliseconds(sum(exact_means[(engine, cell["book"], operation)]
                                                           for cell in books) / 3)})
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
    if any(type(value) is not int for value in times):
        return "missing, reversed, or out-of-order phase endpoints"
    start, engine_start, returned, preparation, ready, end = times
    # Dispatch, the bridge call and the window copy are read on Android's
    # clock, the engine's phases on its own. Across the two clocks, the order
    # holds only within the conversion uncertainty.
    slack = clock["uncertainty_ns"]
    if not (start <= engine_start + slack and engine_start <= returned <= preparation <= ready + slack
            and start <= ready <= end and engine_start < preparation):
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


def _milliseconds(nanoseconds):
    """The float nearest to an exact number of nanoseconds, in milliseconds."""
    return float(Fraction(nanoseconds) / 1_000_000)


def drawing_frame(row):
    """The vsync time and the start of the frame that draws the page, in
    Android nanoseconds, or None for KOReader, which draws without frames.
    Bookfin's is the first frame that showed the page. WebView's is the
    animation frame that was running when preparation ended, if one was;
    otherwise the first frame after preparation."""
    if row["engine"] == "bookfin":
        frame, offset = row["drawn_frame"], row["phase_clock"]["offset_ns"]
        return frame["vsyncStart_us"] * 1000 + offset, frame["buildStart_us"] * 1000 + offset
    if row["engine"] == "webview":
        if row.get("running_frame_vsync_ns") is not None:
            return row["running_frame_vsync_ns"], row["running_frame_start_ns"]
        return row["frame_vsync_ns"], row["frame_start_ns"]
    return None


def frame_wait(row):
    """Nanoseconds from the end of preparation until the vsync of the frame
    that draws the page: the idle wait for the next frame. Zero when that
    vsync came first, as it does for a frame that was already running. Any
    delay after the vsync stays in the interval."""
    frame = drawing_frame(row)
    return 0 if frame is None else max(0, frame[0] - row["preparation_ns"])


def _invalid_drawing(row):
    engine = row["engine"]
    if row.get("drawn_scope") != DRAWN_SCOPES[engine]:
        return "missing or wrong drawing endpoint"
    drawn = row.get("drawn_ns")
    # Bookfin's drawn page is on the engine's clock, WebView's on Android's.
    slack = row["phase_clock"]["uncertainty_ns"]
    before, after = (0, slack) if engine == "bookfin" else (slack, 0)
    if type(drawn) is not int or not row["engine_start_ns"] < drawn + before or not drawn <= row["end_ns"] + after:
        return "drawing endpoint outside the engine interval"
    if engine == "bookfin":
        source = row.get("drawn_source_us")
        if type(source) not in (int, float) or not math.isfinite(source) \
                or abs(source * 1000 + row["phase_clock"]["offset_ns"] - drawn) > 1:
            return "raster finish conversion mismatch"
        frame = row.get("drawn_frame")
        if not isinstance(frame, dict) or any(type(frame.get(phase)) is not int
                                              for phase in ("vsyncStart_us", "buildStart_us", "rasterFinish_us")):
            return "missing drawing frame timing"
        if frame["rasterFinish_us"] != source or not frame["vsyncStart_us"] <= frame["buildStart_us"] \
                or not row["engine_start_source_us"] < frame["buildStart_us"] <= frame["rasterFinish_us"]:
            return "drawing frame does not hold the requested page"
    elif engine == "webview" and drawn < row["engine_ready_ns"]:
        return "visual state callback before it was requested"
    elif engine == "webview":
        times = {}
        for field in ("frame_vsync", "frame_start", "running_frame_vsync", "running_frame_start"):
            value, source = row.get(f"{field}_ns"), row.get(f"{field}_source_ms")
            if field.startswith("running") and value is None and source is None:
                continue
            if type(value) is not int or type(source) not in (int, float) or not math.isfinite(source) \
                    or abs(source * 1_000_000 + row["phase_clock"]["offset_ns"] - value) > 1:
                return "missing frame time or frame time conversion mismatch"
            times[field] = value
        if not times["frame_vsync"] <= times["frame_start"] or not row["preparation_ns"] <= times["frame_start"] < drawn + slack:
            return "frame after preparation outside preparation and drawing"
        if ("running_frame_vsync" in times) != ("running_frame_start" in times) or "running_frame_start" in times \
                and not times["running_frame_vsync"] <= times["running_frame_start"] <= row["preparation_ns"]:
            return "running frame did not start before preparation ended"
    elif engine == "koreader" and drawn != row["preparation_ns"]:
        return "KOReader draws its page in its preparation"
    return None


def kept_frame_wait(row):
    """Nanoseconds from the moment the kept page was handed to the viewport
    until the vsync of the frame that first drew it, or zero when that
    vsync came first. The same rule as `frame_wait`."""
    vsync = row["kept_drawn_frame"]["vsyncStart_us"] * 1000 + row["phase_clock"]["offset_ns"]
    return max(0, vsync - row["kept_ready_ns"])


def _invalid_kept_page(row):
    """Why a cached reopen gives no kept-page sample, or None."""
    if row.get("kept_drawn_scope") != KEPT_SCOPE:
        return f'no kept page drawn: {row.get("kept_status") or "unknown"}'
    if row.get("kept_depicts_page") is not True:
        return "the kept page does not depict the true page"
    offset = row["phase_clock"]["offset_ns"]
    for field in ("kept_ready", "kept_drawn"):
        value, source = row.get(f"{field}_ns"), row.get(f"{field}_source_us")
        if type(value) is not int or type(source) not in (int, float) or not math.isfinite(source) \
                or abs(source * 1000 + offset - value) > 1:
            return "missing kept page time or kept page time conversion mismatch"
    frame = row.get("kept_drawn_frame")
    if not isinstance(frame, dict) or any(type(frame.get(phase)) is not int
                                          for phase in ("vsyncStart_us", "buildStart_us", "rasterFinish_us")):
        return "missing kept page frame timing"
    if frame["rasterFinish_us"] != row["kept_drawn_source_us"] or not frame["vsyncStart_us"] <= frame["buildStart_us"] \
            or not row["engine_start_source_us"] < frame["buildStart_us"] <= frame["rasterFinish_us"] \
            or not row["engine_start_ns"] < row["kept_ready_ns"]:
        return "kept page frame outside the reopen"
    if type(row.get("drawn_ns")) is not int or not row["kept_drawn_ns"] < row["drawn_ns"]:
        return "the kept page did not draw before the true page"
    return None


def _invalid_download_preparation(row):
    """Why a prepared process gives no preparation sample, or None."""
    offset = row["phase_clock"]["offset_ns"]
    for field in ("download_preparation_start", "download_preparation_end"):
        value, source = row.get(f"{field}_ns"), row.get(f"{field}_source_us")
        if type(value) is not int or type(source) not in (int, float) or not math.isfinite(source) \
                or abs(source * 1000 + offset - value) > 1:
            return "missing preparation time or preparation time conversion mismatch"
    if not row["download_preparation_start_ns"] < row["download_preparation_end_ns"] < row["engine_start_ns"]:
        return "preparation at download overlaps the open"
    return None


KEPT_SCOPE = "flutter_raster_finish_of_first_frame_with_kept_page"


# Each interval starts when the engine's own code receives the request. The
# drawn page ends when the engine has drawn the requested page: on the GPU
# for Bookfin and WebView, on the CPU for KOReader. It leaves out only the
# idle wait from the end of preparation until the vsync of the frame that
# draws the page, which only frame-based engines have. The prepared page
# ends before any GPU rasterization or composition.
INTERVALS = {
    "drawn_page": {"start": "engine_start_ns", "end": "drawn_ns", "engines": ENGINES, "scopes": DRAWN_SCOPES,
                   "less": frame_wait, "check": _invalid_drawing,
                   "boundary": "engine_start_ns_to_drawn_ns_less_wait_until_drawing_frame_vsync"},
    "prepared_page": {"start": "engine_start_ns", "end": "preparation_ns",
                      "engines": ENGINES, "scopes": PREPARATION_SCOPES},
    # The kept page that a Bookfin cached reopen draws before its true page
    # (boo-sy2d), with the drawn page's rule for the wait.
    "kept_page": {"start": "engine_start_ns", "end": "kept_drawn_ns", "engines": ("bookfin",),
                  "scopes": {"bookfin": KEPT_SCOPE}, "less": kept_frame_wait, "check": _invalid_kept_page,
                  "select": lambda row: row.get("operation") == "cached_reopen", "operations": ("cached_reopen",),
                  "boundary": "engine_start_ns_to_kept_drawn_ns_less_wait_until_kept_frame_vsync"},
    # The preparation that the app runs in the background when a download
    # completes. It is not on the open's path.
    "download_preparation": {"start": "download_preparation_start_ns", "end": "download_preparation_end_ns",
                             "engines": ("bookfin",),
                             "scopes": {"bookfin": "prepare_downloaded_book_call_to_return"},
                             "check": _invalid_download_preparation,
                             "select": lambda row: row.get("variant") == PREPARED_AT_DOWNLOAD,
                             "operations": (PREPARED_OPEN,)},
    "koreader_before_draw": {"start": "engine_start_ns", "end": "operation_returned_ns",
                             "engines": ("koreader",),
                             "scopes": {"koreader": "koreader_layout_before_drawing"}},
}

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
    if row.get("variant") not in (None, "standard", PREPARED_AT_DOWNLOAD) \
            or row.get("variant") == PREPARED_AT_DOWNLOAD and (row["engine"], row["operation"]) != ("bookfin", "fresh_open"):
        return "unknown process variant"
    expected_cache = {"fresh_open": "fresh_document", PREPARED_OPEN: PREPARED_AT_DOWNLOAD}.get(
        cell_operation(row), "warm_document")
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
