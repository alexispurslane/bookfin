"""The drawing frame and Android's answer for each WebView action (ms).

Usage: python3 webview-answer-gaps.py <samples.jsonl> <tool/research/epub_engines>

For each action, it counts the accepted WebView samples, those whose
preparation ended inside a running animation frame, and those that Android
answered after a later vsync. For the late answers, it gives the time from
the end of preparation to that later vsync, which is an upper bound of the
idle wait that stays in the drawn page, because it also holds the rest of
the drawing frame's work. It also gives the time from the later vsync to
Android's answer. Last, it gives the wait that the drawn page leaves out,
for each engine and action.
"""
import json
import math
import statistics
import sys
from collections import defaultdict

sys.path.insert(0, sys.argv[2])
from collect import accepted, answered_after_a_later_vsync, later_vsync
from results import frame_wait

OPERATIONS = ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change")


def spread(values):
    values = sorted(values)
    if not values:
        return "n=0"
    return (f"median {statistics.median(values):.1f}, p90 {values[math.ceil(.9 * len(values)) - 1]:.1f}, "
            f"n={len(values)}")


rows = [row for row in map(json.loads, open(sys.argv[1])) if accepted(row)]
print("WebView: preparation inside a running frame, and answers after a later vsync")
totals = defaultdict(int)
for operation in OPERATIONS:
    selected = [row for row in rows if row["engine"] == "webview" and row["operation"] == operation]
    running = [row for row in selected if row.get("running_frame_vsync_ns") is not None]
    late = [row for row in selected if answered_after_a_later_vsync(row)]
    totals["samples"] += len(selected)
    totals["running"] += len(running)
    totals["late"] += len(late)
    print(f"{operation}: {len(selected)} samples, {len(running)} inside a running frame, "
          f"{len(late)} answered after a later vsync")
    print(f"  late answers, preparation to later vsync: "
          f"{spread([(later_vsync(row) - row['preparation_ns']) / 1e6 for row in late])}")
    print(f"  late answers, later vsync to answer: "
          f"{spread([(row['drawn_ns'] - later_vsync(row)) / 1e6 for row in late])}")
    print(f"  on-time answers, preparation to answer: "
          f"{spread([(row['drawn_ns'] - row['preparation_ns']) / 1e6 for row in selected if row not in late])}")
print(f"all: {totals['samples']} samples, {totals['running']} inside a running frame, "
      f"{totals['late']} answered after a later vsync")
late = [row for row in rows if row["engine"] == "webview" and answered_after_a_later_vsync(row)]
print(f"all late answers, preparation to later vsync: "
      f"{spread([(later_vsync(row) - row['preparation_ns']) / 1e6 for row in late])}")

print()
print("Wait until the drawing frame's vsync that the drawn page leaves out")
for engine in ("bookfin", "webview"):
    for operation in OPERATIONS:
        waits = [frame_wait(row) / 1e6 for row in rows if row["engine"] == engine and row["operation"] == operation]
        print(f"{engine} {operation}: {sum(wait > 0 for wait in waits)} of {len(waits)} samples wait; "
              f"all samples {spread(waits)}")

print()
print("WebView samples that leave out a wait: where preparation ended after the vsync before the next frame")
waiting = [row for row in rows if row["engine"] == "webview" and frame_wait(row) > 0]
after = [(row["preparation_ns"] - (2 * row["frame_vsync_ns"] - row["next_frame_vsync_ns"])) / 1e6 for row in waiting]
edges = (0, 4, 8, 12, 17)
print(f"{len(waiting)} samples; " + ", ".join(f"{low} to {high} ms: {sum(low <= value < high for value in after)}"
                                            for low, high in zip(edges, edges[1:]))
      + f"; smallest {min(after):.1f}, median {statistics.median(after):.1f}")
print(f"wait left out: {spread([frame_wait(row) / 1e6 for row in waiting])}, largest {max(frame_wait(row) for row in waiting) / 1e6:.1f}")
running = [row for row in rows if row["engine"] == "webview" and row.get("running_frame_vsync_ns") is not None]
print(f"running frames: preparation ended after their vsync: "
      f"{spread([(row['preparation_ns'] - row['running_frame_vsync_ns']) / 1e6 for row in running])}; "
      f"{sum(map(answered_after_a_later_vsync, running))} of {len(running)} answered after a later vsync")
