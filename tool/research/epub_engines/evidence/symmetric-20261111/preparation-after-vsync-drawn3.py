"""Where sym-drawn3 WebView preparation ended relative to the vsync before
the first frame after it, by action (ms), and the wait that the superseded
rule subtracted: from the end of preparation to that frame's first callback.

Usage: python3 preparation-after-vsync-drawn3.py results-drawn3-gpu/samples.jsonl
"""
import json
import statistics
import sys

rows = [row for row in map(json.loads, open(sys.argv[1]))
        if row["engine"] == "webview" and row["measured"] and row.get("content_verified")
        and row.get("window_copy_verified") and not row.get("error")]
for operation in ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change"):
    selected = [row for row in rows if row["operation"] == operation]
    after = [(row["preparation_ns"] - (2 * row["frame_vsync_ns"] - row["next_frame_vsync_ns"])) / 1e6 for row in selected]
    subtracted = [max(0, row["frame_start_ns"] - row["preparation_ns"]) / 1e6 for row in selected]
    print(f"{operation}: {len(selected)} samples; preparation ended a median {statistics.median(after):.1f} ms "
          f"after the vsync before the next frame, {sum(value < 8 for value in after)} within 8 ms; "
          f"the superseded rule subtracted a median {statistics.median(subtracted):.1f} ms")
