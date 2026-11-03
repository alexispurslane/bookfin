import csv
import json
from pathlib import Path
from statistics import mean


directory = Path(__file__).resolve().parent
previous = directory.parents[1] / "20261102" / "android-device"
reports = sorted((directory / "scored").glob("*.json"))
reports += sorted((previous / "scored").glob("*.json"))
summaries = []
rows = []
for path in reports:
    report = json.loads(path.read_text())
    measurements = report["measurements"]
    summary = {
        "report": str(path.relative_to(directory.parents[5])),
        "flavor": report["flavor"],
        "startedWallTimeMs": report["startedWallTimeMs"],
        "completedWallTimeMs": report["completedWallTimeMs"],
        "durationMs": report["completedWallTimeMs"] - report["startedWallTimeMs"],
        "initializationMs": report["initializationMs"],
        "recognitions": len(measurements),
        "meanRecognitionMs": mean(item["recognitionMs"] for item in measurements),
        "memory": report["memory"],
        "quality": [
            {key: item[key] for key in ("sample", "repetition", "quality")}
            for item in measurements if item["quality"] is not None
        ],
    }
    summaries.append(summary)
    for item in measurements:
        rows.append({
            "report": summary["report"],
            "flavor": report["flavor"],
            "sample": item["sample"],
            "repetition": item["repetition"],
            "recognitionMs": item["recognitionMs"],
            "decodeAndRecognitionMs": item["decodeAndRecognitionMs"],
            "decodeAndInputOverheadMs": item["decodeAndRecognitionMs"] - item["recognitionMs"],
            "wordErrors": item["quality"]["wordErrors"] if item["quality"] else "",
            "referenceWords": item["quality"]["referenceWords"] if item["quality"] else "",
        })

output = {
    "sourceCommit": "838d8a4a0b6f2a55f0042df042ab5f5b97df51df",
    "sourceArchiveSha256": "d723f7bc35de18ef92ec727957dd591a8d42690a9eb58602c124f5009feae0a7",
    "scope": "Separate offline emulator research, not production acceptance or engine selection",
    "renewedCompletedRecognitions": sum(item["recognitions"] for item in summaries if "20261103" in item["report"]),
    "retainedPreviousRecognitions": sum(item["recognitions"] for item in summaries if "20261102" in item["report"]),
    "mlkitActiveCancellationProved": False,
    "mlkitActiveDepartureProved": False,
    "reports": summaries,
}
(directory / "summary.json").write_text(json.dumps(output, indent=2) + "\n")
with (directory / "measurements.csv").open("w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)

table = [
    "| Report | Initialization ms | Duration ms | Sampled maximum PSS KiB | Native allocated bytes | Java used bytes | Samples |",
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
]
for summary in summaries:
    memory = summary["memory"]
    table.append(
        f"| {Path(summary['report']).stem} | {summary['initializationMs']:.3f} | {summary['durationMs']} | "
        f"{memory['sampledPeakProcessPssKiB']} | {memory['sampledPeakNativeAllocatedBytes']} | "
        f"{memory['sampledPeakJavaUsedBytes']} | {memory['samples']} |"
    )
(directory / "report-table.md").write_text("\n".join(table) + "\n")

print(json.dumps({key: value for key, value in output.items() if key != "reports"}, indent=2))
for summary in summaries:
    if Path(summary["report"]).stem.endswith("fresh"):
        print(Path(summary["report"]).stem, "mean recognition ms", summary["meanRecognitionMs"])
