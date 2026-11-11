"""The hop from the Java shell's dispatch to the engine's first timestamp, for
each accepted measured WebView and KOReader sample, against that sample's
clock conversion uncertainty (ms).

Usage: python3 bridge-hop-check.py <samples.jsonl> <tool/research/epub_engines>
"""
import json
import statistics
import sys

sys.path.insert(0, sys.argv[2])
from collect import accepted

rows = [row for row in map(json.loads, open(sys.argv[1])) if accepted(row)]
for engine in ("webview", "koreader"):
    selected = [row for row in rows if row["engine"] == engine]
    hops = [(row["engine_start_ns"] - row["start_ns"]) / 1e6 for row in selected]
    uncertainties = [row["phase_clock"]["uncertainty_ns"] / 1e6 for row in selected]
    within = sum(hop < uncertainty for hop, uncertainty in zip(hops, uncertainties))
    print(f"{engine}: {len(selected)} samples; hop median {statistics.median(hops):.3f}, smallest {min(hops):.3f}; "
          f"uncertainty median {statistics.median(uncertainties):.3f}, largest {max(uncertainties):.3f}; "
          f"{within} samples with a hop smaller than their own uncertainty")
