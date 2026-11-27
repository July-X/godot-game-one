"""Capture and exercise the real title and LAN lobby with Godot."""
import argparse
import os
import subprocess
import time
from pathlib import Path

SIZES = {"wide": "1600x720", "tablet": "960x720", "stacked": "540x720"}


def start(folder, role, aspect, capture, position="30,35", *, system_back=False):
    display = (["--windowed", "--resolution", SIZES[aspect], "--position", position]
               if capture else ["--headless"])
    log = folder / f"{role}-{aspect}.log"
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(
            [os.getenv("GODOT", "godot"), "--path", ".", *display, "--audio-driver", "Dummy",
             "res://tests/entry_ui_probe.tscn", "--", role, aspect, str(folder) if capture else "",
             *(["system-back"] if system_back else [])],
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


def run_walk(folder, aspect, capture, *, role="walk"):
    job = start(folder, role, aspect, capture)
    try:
        return passed(job, 70)
    except subprocess.TimeoutExpired:
        return False
    finally:
        cleanup([job])


def run_live(folder, capture, *, system_back=False):
    jobs = []
    try:
        jobs.append(start(folder, "old", "wide", False, system_back=system_back))
        jobs.append(start(folder, "host", "wide", capture, "5,35", system_back=system_back))
        if not (ready(jobs[0], "[ENTRY_UI] OLD_READY") and ready(jobs[1], "[ENTRY_UI] HOST_READY")):
            return False
        jobs.append(start(folder, "join", "tablet", capture, "285,150", system_back=system_back))
        return all([passed(job, 42) for job in jobs])
    except subprocess.TimeoutExpired:
        return False
    finally:
        cleanup(jobs)


def expected_system_exit(job, marker, timeout):
    process, log = job
    exited = process.wait(timeout) == 0
    content = log.read_text(encoding="utf-8")
    return (exited and marker in content and "pass=false" not in content and "[ENTRY_UI] SUMMARY" not in content
            and not any(line.startswith(("SCRIPT ERROR", "ERROR:")) for line in content.splitlines()))


def run_back(folder):
    folder.mkdir(exist_ok=True)
    results = {f"back-{aspect}": run_walk(folder, aspect, False, role="back") for aspect in ("wide", "tablet")}
    results["back-live"] = run_live(folder, False, system_back=True)
    jobs = []
    try:
        jobs.append(start(folder, "title-back", "wide", False))
        results["back-title-exit"] = expected_system_exit(jobs[-1], "[ENTRY_UI] TITLE_BACK", 10)
        jobs.append(start(folder, "battle-host", "tablet", False))
        results["back-battle"] = False
        if ready(jobs[-1], "[ENTRY_UI] BATTLE_HOST_READY"):
            jobs.append(start(folder, "battle-join", "wide", False))
            exited = expected_system_exit(jobs[-2], "[ENTRY_UI] BATTLE_BACK", 20)
            results["back-battle"] = passed(jobs[-1], 15) and exited
    except subprocess.TimeoutExpired:
        results.setdefault("back-title-exit", False)
        results.setdefault("back-battle", False)
    finally:
        cleanup(jobs)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--case", choices=("walk", "live", "back"), action="append")
    parser.add_argument("--format", choices=SIZES, action="append")
    args = parser.parse_args()
    folder = args.output.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    cases = args.case or ("walk", "live", "back")
    results = {}
    if "walk" in cases:
        for aspect in args.format or SIZES:
            results["walk-" + aspect] = run_walk(folder, aspect, args.capture and aspect != "stacked")
    if "live" in cases:
        results["live"] = run_live(folder, args.capture)
    if "back" in cases:
        results.update(run_back(folder / "back"))
    for case, success in results.items():
        print(f"{case} passed={success}")
    return int(not all(results.values()))


if __name__ == "__main__":
    raise SystemExit(main())
