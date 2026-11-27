"""Capture and exercise the real title and LAN lobby with Godot."""
import argparse
import os
import subprocess
import time
from pathlib import Path

SIZES = {"wide": "1600x720", "tablet": "960x720", "stacked": "540x720"}


def start(folder, role, aspect, capture, position="30,35"):
    display = (["--windowed", "--resolution", SIZES[aspect], "--position", position]
               if capture else ["--headless"])
    log = folder / f"{role}-{aspect}.log"
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(
            [os.getenv("GODOT", "godot"), "--path", ".", *display, "--audio-driver", "Dummy",
             "res://tests/entry_ui_probe.tscn", "--", role, aspect, str(folder) if capture else ""],
            stdout=stream, stderr=subprocess.STDOUT)
    return process, log


def ready(job, marker):
    process, log = job
    until = time.monotonic() + 12
    while process.poll() is None and time.monotonic() < until:
        if marker in log.read_text(encoding="utf-8"):
            return True
        time.sleep(.05)
    return False


def passed(job, timeout):
    process, log = job
    result = process.wait(timeout)
    content = log.read_text(encoding="utf-8")
    return (result == 0 and "[ENTRY_UI] SUMMARY" in content and "failed=0" in content
            and not any(line.startswith(("SCRIPT ERROR", "ERROR:")) and "resources still in use at exit" not in line
                        for line in content.splitlines()))


def cleanup(jobs):
    for process, _ in jobs:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)


def run_walk(folder, aspect, capture):
    job = start(folder, "walk", aspect, capture)
    try:
        return passed(job, 70)
    except subprocess.TimeoutExpired:
        return False
    finally:
        cleanup([job])


def run_live(folder, capture):
    jobs = []
    try:
        jobs.append(start(folder, "old", "wide", False))
        jobs.append(start(folder, "host", "wide", capture, "5,35"))
        if not (ready(jobs[0], "[ENTRY_UI] OLD_READY") and ready(jobs[1], "[ENTRY_UI] HOST_READY")):
            return False
        jobs.append(start(folder, "join", "tablet", capture, "285,150"))
        return all([passed(job, 42) for job in jobs])
    except subprocess.TimeoutExpired:
        return False
    finally:
        cleanup(jobs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--case", choices=("walk", "live"), action="append")
    parser.add_argument("--format", choices=SIZES, action="append")
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    cases = args.case or ("walk", "live")
    results = {}
    if "walk" in cases:
        for aspect in args.format or SIZES:
            results["walk-" + aspect] = run_walk(folder, aspect, args.capture and aspect != "stacked")
    if "live" in cases:
        results["live"] = run_live(folder, args.capture)
    for case, success in results.items():
        print(f"{case} passed={success}")
    return int(not all(results.values()))


if __name__ == "__main__":
    raise SystemExit(main())
