import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess

from protocol import schedule


PACKAGES = {"bookfin": "dev.bookfin.bench.bookfin_epub_shell",
            "webview": "dev.bookfin.bench.epub.webview",
            "koreader": "dev.bookfin.bench.epub.koreader"}


def run(arguments, log, allow_failure=False):
    completed = subprocess.run(arguments, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=390)
    log.write(json.dumps({"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                          "command": arguments, "exit": completed.returncode,
                          "output": completed.stdout}) + "\n")
    log.flush()
    if completed.returncode and not allow_failure:
        raise RuntimeError(f"Command failed ({completed.returncode}): {arguments[0]}")
    return completed.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--calibration", action="store_true")
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--prefix", default="")
    parser.add_argument("--serial", required=True, help="adb serial of the emulator that this run owns")
    args = parser.parse_args()
    if os.environ.get("BOOKFIN_NIX_SHELL") != "1":
        raise RuntimeError("Run through the project Nix dev shell")
    jobs = schedule()
    if args.calibration:
        jobs = [{**job, "run_id": f'calibration-{job["book"]}-{job["engine"]}', "round": -1}
                for job in jobs[:9]]
    if args.prefix:
        jobs = [{**job, "run_id": ("calibration-" if args.calibration else "") + args.prefix + "-" + job["run_id"]} for job in jobs]
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "schedule.json").write_text(json.dumps(jobs, indent=2) + "\n")
    with (args.output / "commands.jsonl").open("a") as log:
        for index, job in enumerate(jobs):
            if index < args.start or (args.limit is not None and index >= args.start + args.limit):
                continue
            package = PACKAGES[job["engine"]]
            destination = args.output / job["run_id"]
            if destination.exists():
                raise RuntimeError(f"Refusing to overwrite previous evidence: {destination}")
            print(f'{index+1}/{len(jobs)} {job["run_id"]}', flush=True)
            remote = f'/sdcard/Android/data/{package}/files/runs/{job["run_id"]}'
            output = run(["adb", "-s", args.serial, "shell", "am", "instrument", "-w", "-r",
                          "-e", "class", "dev.bookfin.bench.epub.EngineWorkloadTest",
                          "-e", "book", job["book"], "-e", "run", job["run_id"],
                          "-e", "round", str(job["round"]),
                          package + ".test/androidx.test.runner.AndroidJUnitRunner"], log)
            (args.output / (job["run_id"] + "-instrumentation.txt")).write_text(output)
            run(["adb", "-s", args.serial, "pull", remote, str(destination)], log, allow_failure="OK (1 test)" not in output)
            if "OK (1 test)" not in output:
                raise RuntimeError(f'Instrumented behavior test failed: {job["run_id"]}; output and raw evidence retained')
            records = [json.loads(path.read_text()) for path in destination.glob("[0-9]*.json")]
            if len(records) != len(job["steps"]):
                raise RuntimeError(f'Incomplete workload: {job["run_id"]}')
            failures = [row for row in records if row.get("error")]
            if failures:
                raise RuntimeError(f'Failed window/destination check: {job["run_id"]}; inspect raw records')


if __name__ == "__main__":
    main()
