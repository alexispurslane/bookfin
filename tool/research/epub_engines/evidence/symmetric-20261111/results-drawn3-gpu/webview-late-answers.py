"""WebView answers after a later vsync, by action, and the frame work of on-time and late answers (ms)."""
import json, math, statistics, sys
from collections import Counter
sys.path.insert(0, sys.argv[2])
from collect import answered_after_a_later_vsync

rows = [json.loads(line) for line in open(sys.argv[1])]
accepted = [row for row in rows if row["engine"] == "webview" and row["measured"] and row.get("content_verified")
            and row.get("window_copy_verified") and not row.get("error")]
late, total, work = Counter(), Counter(), {True: [], False: []}
for row in accepted:
    answer = answered_after_a_later_vsync(row)
    late[row["operation"]] += answer
    total[row["operation"]] += 1
    work[answer].append((row["drawn_ns"] - max(row["frame_start_ns"], row["preparation_ns"])) / 1e6)
for operation in ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change"):
    print(f"{operation}: {late[operation]} of {total[operation]} answered after a later vsync")
print(f"all: {sum(late.values())} of {sum(total.values())}")
for answer, label in ((False, "on time"), (True, "after a later vsync")):
    values = sorted(work[answer])
    print(f"frame work, {label}: median {statistics.median(values):.1f}, p90 {values[math.ceil(.9 * len(values)) - 1]:.1f}, n={len(values)}")
