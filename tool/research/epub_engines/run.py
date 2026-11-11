import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import threading
import time

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


# Other agents share this host. A job counts only if the one-minute host load
# stayed under this limit from its start to its end.
LOAD_LIMIT = 8.0


def quiet_host(load, sleep, limit, checks):
    """Waits until the one-minute host load is under the limit and returns it."""
    for _ in range(checks):
        value = load()
        if value < limit:
            return value
        sleep(10)
    raise RuntimeError(f"Host load stayed at or above {limit}; no job was measured")


def measure_quietly(run_id, attempt, load, sleep, output, limit, attempts=3):
    """Measures one job until a whole attempt ran with the host load under the
    limit. `attempt` runs the job and returns the highest load sampled during
    it. Each busy attempt's evidence moves to rejected-load/, and the job runs
    again in the same place in the schedule."""
    for number in range(1, attempts + 1):
        before = quiet_host(load, sleep, limit, checks=180)
        peak = attempt()
        accepted = peak < limit
        with (output / "host-load.jsonl").open("a") as log:
            log.write(json.dumps({"run_id": run_id, "attempt": number, "utc": _utc(),
                                  "load_before": before, "peak_load": peak, "limit": limit,
                                  "accepted": accepted}) + "\n")
        if accepted:
            return
        rejected = output / "rejected-load"
        rejected.mkdir(exist_ok=True)
        for source, name in ((output / run_id, f"{run_id}-attempt-{number}"),
                             (output / f"{run_id}-instrumentation.txt", f"{run_id}-attempt-{number}-instrumentation.txt")):
            if source.exists():
                source.rename(rejected / name)
    raise RuntimeError(f"{run_id} never ran with the host load under {limit}")


def sampled(task, load, interval=1.0):
    """Runs `task` while reading the host load every interval; returns its
    result and the highest load read."""
    readings = [load()]
    done = threading.Event()

    def sample():
        while not done.wait(interval):
            readings.append(load())

    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    try:
        result = task()
    finally:
        done.set()
        sampler.join()
    readings.append(load())
    return result, max(readings)


def _utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


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
    load = lambda: os.getloadavg()[0]
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

            def attempt(job=job, package=package, remote=remote, destination=destination):
                run(["adb", "-s", args.serial, "shell", "rm", "-rf", remote], log)
                output, peak = sampled(lambda: run(
                    ["adb", "-s", args.serial, "shell", "am", "instrument", "-w", "-r",
                     "-e", "class", "dev.bookfin.bench.epub.EngineWorkloadTest",
                     "-e", "book", job["book"], "-e", "run", job["run_id"],
                     "-e", "round", str(job["round"]),
                     package + ".test/androidx.test.runner.AndroidJUnitRunner"], log), load)
                (args.output / (job["run_id"] + "-instrumentation.txt")).write_text(output)
                run(["adb", "-s", args.serial, "pull", remote, str(destination)], log, allow_failure="OK (1 test)" not in output)
                if "OK (1 test)" not in output:
                    raise RuntimeError(f'Instrumented behavior test failed: {job["run_id"]}; output and raw evidence retained')
                return peak

            measure_quietly(job["run_id"], attempt, load, time.sleep, args.output, LOAD_LIMIT)
            records = [json.loads(path.read_text()) for path in destination.glob("[0-9]*.json")]
            if len(records) != len(job["steps"]):
                raise RuntimeError(f'Incomplete workload: {job["run_id"]}')
            failures = [row for row in records if row.get("error")]
            if failures:
                raise RuntimeError(f'Failed window/destination check: {job["run_id"]}; inspect raw records')


if __name__ == "__main__":
    main()
