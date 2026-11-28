"""Run the same ordinary title/lobby route against the baseline and current code."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/player_growth_probe.tscn"
BASELINE = "43a52d69ebb653917e1606e0378353cb18dc9273"


def run(project, output, label, roles, port, candidate):
    jobs = []
    paths = []
    try:
        for role in roles:
            path = output / f"{label}-{role}.log"
            paths.append(path)
            args = ["--fixed-fps", "60", "--quit-after", "21000"] if role == "solo" else []
            user_args = [role, str(port), "normal", "device-a" if role == "host" else "device-b"]
            if candidate:
                user_args.append("candidate")
            with path.open("w") as log:
                jobs.append(subprocess.Popen(
                    [GODOT, "--headless", "--path", str(project), *args, SCENE, "--", *user_args],
                    stdout=log, stderr=subprocess.STDOUT))
            if role == "host":
                time.sleep(.35)
        codes = [job.wait(timeout=150) for job in jobs]
    except subprocess.TimeoutExpired:
        codes = []
    finally:
        for job in jobs:
            if job.poll() is None:
                job.terminate()
                job.wait(timeout=5)
    ok = codes == [0] * len(roles)
    if not ok:
        print(label, "process exit codes:", codes, flush=True)
    for path in paths:
        lines = path.read_text().splitlines()
        summaries = [line for line in lines if "SUMMARY pass=" in line]
        ok &= bool(summaries) and all("failed=0" in line for line in summaries)
        ok &= not any(line.lstrip().startswith(("SCRIPT ERROR", "ERROR:")) for line in lines)
        print(path.name, *summaries, flush=True)
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--baseline", type=Path, help="Already imported baseline project")
    parser.add_argument("--mode", choices=("solo", "lan", "both"), default="both")
    parser.add_argument("--port", type=int, default=24880)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="growth-ab-") as temp:
        baseline = args.baseline.resolve() if args.baseline else Path(temp)
        if not args.baseline:
            archive = baseline / "baseline.tar"
            subprocess.run(["git", "archive", "-o", str(archive), BASELINE], cwd=project, check=True)
            subprocess.run(["tar", "xf", str(archive), "-C", str(baseline)], check=True)
            with (output / "baseline-import.log").open("w") as log:
                subprocess.run([GODOT, "--headless", "--path", str(baseline), "--editor", "--import", "--quit"],
                               stdout=log, stderr=subprocess.STDOUT, timeout=120, check=True)
        for filename in ("player_growth_probe.gd", "player_growth_probe.tscn"):
            shutil.copy2(project / "tests" / filename, baseline / "tests" / filename)
        cases = []
        if args.mode != "lan":
            cases.append(("solo", ("solo",)))
        if args.mode != "solo":
            cases.append(("lan", ("host", "client")))
        outcomes = []
        for name, roles in cases:
            for root, tag, candidate in ((baseline, "A", False), (project, "B", True)):
                outcomes.append(run(root, output, f"{tag}-{name}", roles, args.port + int(candidate), candidate))
        return int(not all(outcomes))


if __name__ == "__main__":
    raise SystemExit(main())
