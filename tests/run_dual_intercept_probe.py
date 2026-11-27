"""Drive the prototype from the real lobby and keep each peer's full log."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path

CASES = ("center", "left", "right", "both", "both-no-pulse", "late", "downed", "mismatch")


def run_pair(destination, mode, wide_host, capture, legacy_host=None, legacy_client=None):
    folder = destination / mode
    folder.mkdir(parents=True, exist_ok=True)
    logs = [folder / "host.log", folder / "client.log"]
    jobs = []
    godot = os.getenv("GODOT", "godot")
    legacy_args = (["review-legacy-host"] if legacy_host else ["review-legacy-client"] if legacy_client else [])
    try:
        for host, log in zip((True, False), logs):
            wide = host == wide_host
            project = (legacy_host if host else legacy_client) or Path.cwd()
            display = (["--windowed", "--resolution", "1600x720" if wide else "960x720",
                        "--position", "5,35" if host else "240,110"] if capture else ["--headless"])
            with log.open("w", encoding="utf-8") as stream:
                jobs.append(subprocess.Popen([godot, "--path", str(project)] + display + ["--audio-driver", "Dummy",
                    "res://tests/dual_intercept_probe.tscn", "--", "host" if host else "client", mode,
                    "wide" if wide else "tablet", str(folder) if capture else "", "--rift-log"] + legacy_args,
                    stdout=stream, stderr=subprocess.STDOUT))
            if host:
                limit = time.monotonic() + 12
                while "[DUAL] host_ready" not in log.read_text(encoding="utf-8"):
                    if jobs[0].poll() is not None or time.monotonic() >= limit:
                        return False
                    time.sleep(.05)
        codes = [job.wait(timeout=105 if mode == "sequence" else 82) for job in jobs]
        return codes == [0, 0] and all(
            "[DUAL] SUMMARY" in content and not any(line.startswith(("ERROR:", "SCRIPT ERROR"))
                and "resources still in use at exit" not in line for line in content.splitlines())
            for content in (log.read_text(encoding="utf-8") for log in logs))
    except subprocess.TimeoutExpired:
        return False
    finally:
        for job in jobs:
            if job.poll() is None:
                job.terminate()
                job.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--case", action="append", choices=(*CASES, "sequence"))
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--tablet-first", action="store_true")
    legacy = parser.add_mutually_exclusive_group()
    legacy.add_argument("--legacy-host", type=Path)
    legacy.add_argument("--legacy-client", type=Path)
    args = parser.parse_args()
    output = args.destination.resolve()
    results = []
    for index, mode in enumerate(args.case or CASES):
        wide_host = (index % 2 == 0) != args.tablet_first
        results.append({"case": mode, "host": "20:9" if wide_host else "4:3",
                        "passed": run_pair(output, mode, wide_host, args.capture and mode != "mismatch",
                                           args.legacy_host, args.legacy_client)})
        print(json.dumps(results[-1]), flush=True)
    (output / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(not all(row["passed"] for row in results))


if __name__ == "__main__":
    raise SystemExit(main())
