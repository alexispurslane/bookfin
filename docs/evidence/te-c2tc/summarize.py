"""Extract results and skip reasons from the retained Flutter JSON reporters."""
import gzip
import json
from pathlib import Path

root = Path(__file__).resolve().parents[3]
evidence = root / "docs/evidence/te-c2tc"
summaries = []
for record in map(json.loads, (evidence / "commands.jsonl").read_text().splitlines()):
    if "json" not in record["command"] or "test" not in record["command"]:
        continue
    events = []
    for line in gzip.decompress((root / record["log"]["path"]).read_bytes()).decode().splitlines():
        try:
            events.append(json.loads(line))
        except ValueError:
            pass  # Startup SDK notices are retained in the complete log.
    tests = {e["test"]["id"]: e["test"] for e in events if e.get("type") == "testStart"}
    suites = {e["suite"]["id"]: e["suite"] for e in events if e.get("type") == "suite"}
    done = [e for e in events if e.get("type") == "testDone" and not e["hidden"]]
    skips = []
    for event in done:
        if not event["skipped"]:
            continue
        test = tests[event["testID"]]
        path = Path(suites[test["suiteID"]]["path"])
        messages = [e["message"] for e in events if e.get("type") == "print"
                    and e.get("testID") == test["id"] and e.get("messageType") == "skip"]
        gates = []
        if not messages and not test["metadata"].get("skipReason"):
            lines = path.read_text().splitlines()
            gates = [{"line": i + 1, "source": "\n".join(lines[max(0, i - 2):i + 3])}
                     for i, line in enumerate(lines) if "skip:" in line or "markTestSkipped" in line]
        skips.append({"file": str(path.relative_to(root)), "name": test["name"],
                      "reason": test["metadata"].get("skipReason"), "messages": messages,
                      "booleanGateSource": gates})
    summary = {
        "commandName": record["name"], "command": record["command"], "exit": record["exit"],
        "passed": sum(e["result"] == "success" and not e["skipped"] for e in done),
        "failed": sum(e["result"] != "success" for e in done), "skipped": len(skips),
        "failures": [tests[e["testID"]] for e in done if e["result"] != "success"],
        "skips": skips, "log": record["log"],
        "completion": [e for e in events if e.get("type") == "done"],
    }
    summaries.append(summary)
(evidence / "test-results.json").write_text(json.dumps(summaries, indent=2) + "\n")
for summary in summaries:
    print({k: summary[k] for k in ["commandName", "exit", "passed", "failed", "skipped"]})
