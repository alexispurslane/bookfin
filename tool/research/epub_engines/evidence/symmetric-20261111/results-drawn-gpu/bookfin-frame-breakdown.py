"""Bookfin: time from preparation to the drawn frame's phases, from accepted samples (ms)."""
import json, statistics, sys
rows = [json.loads(line) for line in open(sys.argv[1])]
def quantiles(values):
    values = sorted(values)
    return "median %.2f, p90 %.2f, max %.2f (n=%d)" % (statistics.median(values), values[-(-9 * len(values) // 10) - 1], values[-1], len(values))
for operation in ("fresh_open", "cached_reopen", "page_turn", "chapter_crossing", "font_change"):
    accepted = [row for row in rows if row["engine"] == "bookfin" and row["operation"] == operation and row["measured"]
                and row.get("content_verified") and row.get("window_copy_verified") and not row.get("error")]
    phase = lambda row, name: row["drawn_frame"][name + "_us"]
    print(operation)
    print("  preparation to vsyncStart:", quantiles([(phase(r, "vsyncStart") - r["preparation_source_us"]) / 1e3 for r in accepted]))
    print("  vsyncStart to rasterStart:", quantiles([(phase(r, "rasterStart") - phase(r, "vsyncStart")) / 1e3 for r in accepted]))
    print("  rasterStart to rasterFinish:", quantiles([(phase(r, "rasterFinish") - phase(r, "rasterStart")) / 1e3 for r in accepted]))
    print("  preparation to drawn:", quantiles([(r["drawn_ns"] - r["preparation_ns"]) / 1e6 for r in accepted]))
