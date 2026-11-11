"""Recomputes every cell (median, p90, mean) and equal-book mean of each interval from the accepted
samples in exact rational nanoseconds, independently of results.py, and compares the half-up rounding
to tenths of a millisecond with what tables.py prints. Usage: exact-rounding-check.py RESULTS_DIR... """
import json, math, sys
from collections import defaultdict
from decimal import ROUND_HALF_UP, Decimal
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tables import _ms

ENDS = {"drawn_page": "drawn_ns", "prepared_page": "preparation_ns", "koreader_before_draw": "operation_returned_ns"}


def wait(row):
    """The superseded rule: the wait until the drawing frame starts."""
    if row["engine"] == "bookfin":
        start = row["drawn_frame"]["buildStart_us"] * 1000 + row["phase_clock"]["offset_ns"]
    elif row["engine"] == "webview":
        start = row["frame_start_ns"]
    else:
        return 0
    return max(0, start - row["preparation_ns"])


def vsync_wait(row):
    """The current rule: the wait until the drawing frame's vsync. For WebView,
    the running frame draws the page if preparation ended inside one."""
    if row["engine"] == "bookfin":
        vsync = row["drawn_frame"]["vsyncStart_us"] * 1000 + row["phase_clock"]["offset_ns"]
    elif row["engine"] == "webview":
        running = row.get("running_frame_vsync_ns")
        vsync = running if running is not None else row["frame_vsync_ns"]
    else:
        return 0
    return max(0, vsync - row["preparation_ns"])


# Each summary names the rule of its drawn-page cells in their boundary.
WAITS = {"engine_start_ns_to_drawn_ns": wait,
         "engine_start_ns_to_drawn_ns_less_wait_until_drawing_frame_vsync": vsync_wait}


def tenth(value):
    return str((Decimal(value.numerator) / Decimal(value.denominator)).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


total = mismatches = 0
for directory in map(Path, sys.argv[1:]):
    summary = json.loads((directory / "summary.json").read_text())
    rows = [json.loads(line) for line in (directory / "samples.jsonl").read_text().splitlines()]
    accepted = [row for row in rows if row["measured"] and row.get("content_verified")
                and row.get("window_copy_verified") and not row.get("error")]
    for name, interval in summary["intervals"].items():
        excluded = {entry["id"] for entry in interval["excluded"]}
        less = WAITS[interval["cells"][0]["boundary"]] if name == "drawn_page" and interval["cells"] else (lambda row: 0)
        groups = defaultdict(list)
        for row in accepted:
            if row["id"] in excluded or (name == "koreader_before_draw" and row["engine"] != "koreader"):
                continue
            groups[(row["engine"], row["book"], row["operation"])].append(
                Fraction(row[ENDS[name]] - row["engine_start_ns"] - less(row), 1_000_000))
        for cell in interval["cells"]:
            values = sorted(groups[(cell["engine"], cell["book"], cell["operation"])])
            count = len(values)
            median = values[count // 2] if count % 2 else (values[count // 2 - 1] + values[count // 2]) / 2
            checks = ((median, cell["median_ms"]), (values[math.ceil(count * Fraction(9, 10)) - 1], cell["p90_ms"]),
                      (sum(values) / count, cell["mean_ms"]))
            for exact, stored in checks:
                total += 1
                if tenth(exact) != _ms(stored) or count != cell["count"]:
                    mismatches += 1
                    print("MISMATCH", directory.name, name, cell["engine"], cell["book"], cell["operation"], tenth(exact), _ms(stored))
        for mean in interval["equal_book_means"]:
            books = [groups[(mean["engine"], book, mean["operation"])] for book in ("prose", "long", "illustrated")]
            exact = sum(sum(values) / len(values) for values in books) / 3
            total += 1
            if tenth(exact) != _ms(mean["mean_ms"]):
                mismatches += 1
                print("MISMATCH", directory.name, name, mean["engine"], "mean", mean["operation"], tenth(exact), _ms(mean["mean_ms"]))
print(f"{total} rounded values checked, {mismatches} mismatches")
