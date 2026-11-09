"""Summarize results.jsonl from the test app or bin/mac_check.dart.

Usage: python3 -I summarize.py results.jsonl
Prints Markdown tables: one row per run (load, first clause cold and warm,
RTF, peak memory, battery), then per-minute RTF of each run that lasts over
five minutes, with the phone readings of that minute.
RTF = synthesis time / audio duration, summed over the sentences.
"""
import json
import sys
from collections import defaultdict

events = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
runs = defaultdict(list)
phone = [e for e in events if e["event"] == "phone"]
for e in events:
    if "label" in e:
        runs[e["label"]].append(e)


def phone_between(a, b):
    return [p for p in phone if a <= p["epochMs"] <= b]


print("| Run | Load s | First clause cold s | warm s | Sentences | Audio min | RTF | Peak MB | Battery % used | Thermal status at end |")
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for label, es in runs.items():
    ev = {e["event"]: e for e in es}
    if "error" in ev:
        print(f"| {label} | error: {ev['error']['error'][:80]} |")
        continue
    ss = [e for e in es if e["event"] == "sentence"]
    if not ss:
        continue
    ms, au = sum(e["ms"] for e in ss), sum(e["audioMs"] for e in ss)
    peak = max(e["hwmKb"] for e in es) / 1024
    a, b = es[0].get("epochMs", 0), es[-1].get("epochMs", 0)
    ph = phone_between(a, b)
    used = (ph[0]["batteryPct"] - ph[-1]["batteryPct"]) if len(ph) > 1 else ""
    end = ph[-1]["thermalStatus"] if ph else ""
    print(
        f"| {label} | {ev['load']['ms']/1000:.2f} | {ev['firstClauseCold']['ms']/1000:.2f} "
        f"| {ev['firstClauseWarm']['ms']/1000:.2f} | {len(ss)} | {au/60000:.1f} | {ms/au:.3f} "
        f"| {peak:.0f} | {used} | {end} |"
    )

for label, es in runs.items():
    ss = [e for e in es if e["event"] == "sentence"]
    if not ss or ss[-1]["t"] - ss[0]["t"] < 300_000:
        continue
    t0 = ss[0]["t"] - ss[0]["ms"]
    mins = defaultdict(lambda: [0, 0])
    for e in ss:
        m = (e["t"] - t0) // 60000
        mins[m][0] += e["ms"]
        mins[m][1] += e["audioMs"]
    e0 = ss[0]["epochMs"] - (ss[0]["t"] - t0)
    print(f"\n{label}, per minute of wall time:\n")
    print("| Minute | RTF | Thermal status | Headroom (10 s) | Battery % | Battery current mA | Battery °C |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    for m in sorted(mins):
        ms, au = mins[m]
        ph = phone_between(e0 + m * 60000, e0 + (m + 1) * 60000)
        p = ph[-1] if ph else {}
        cur = p.get("currentUa")
        print(
            f"| {m + 1} | {ms/au:.3f} | {p.get('thermalStatus', '')} | "
            f"{p.get('headroom10s', float('nan')):.2f} | {p.get('batteryPct', '')} | "
            f"{'' if cur is None else round(cur / 1000)} | {p.get('batteryTempC', '')} |"
        )
