"""Compare first-Boss pacing through the real title and LAN lobby."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from run_player_growth_probe import BASELINE, GODOT


ROOT = Path(__file__).resolve().parents[1]
ACCEPTED = "0d46ab2bc06d1788cc68902861cad4fc698e317d"
ENEMY_SCRIPT = "scripts/battle/enemies/enemy.gd"
PROBES = ("player_growth_probe.gd", "first_boss_pace_probe.gd", "first_boss_pace_probe.tscn")
CASES = {
    "solo-anchor": ("solo", 1121, "anchor"),
    "solo-1122": ("solo", 1122, "patrol"),
    "solo-1123": ("solo", 1123, "patrol"),
    "lan-anchor": ("lan", 1121, "anchor"),
    "lan-patrol": ("lan", 1122, "patrol"),
}


def archive(path, variant, output):
    path.mkdir()
    ref = ACCEPTED if variant == "B" else BASELINE
    archive_path = path / "archive.tar"
    subprocess.run(["git", "archive", "-o", str(archive_path), ref], cwd=ROOT, check=True)
    subprocess.run(["tar", "-xf", str(archive_path), "-C", str(path)], check=True)
    if variant == "D":
        # Isolate death deduplication on A. Do not pick up any cannon, draft, or HUD changes.
        source = subprocess.check_output(["git", "show", f"{ACCEPTED}:{ENEMY_SCRIPT}"], cwd=ROOT)
        (path / ENEMY_SCRIPT).write_bytes(source)
    for name in PROBES:
        shutil.copyfile(ROOT / "tests" / name, path / "tests" / name)
    with (output / f"{variant}-import.log").open("w") as log:
        subprocess.run([GODOT, "--headless", "--path", str(path), "--editor", "--import", "--quit"],
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
    return path


def run(job):
    variant, project, case, out, port = job
    mode, seed, route = CASES[case]
    roles = ("solo",) if mode == "solo" else ("host", "client")
    processes = []
    paths = {}
    codes = []
    try:
        for role in roles:
            path = out / f"{variant}-{case}-{role}.log"
            paths[role] = path
            options = ["--fixed-fps", "60", "--quit-after", "22000"] if mode == "solo" else []
            args = [role, str(port), "normal", f"seed={seed}"]
            if mode == "lan":
                args.append("device-a" if role == "host" else "device-b")
            if route == "patrol":
                args += ["patrol", "choose"]
            if variant == "C":
                args.append("candidate")
            with path.open("w") as log:
                processes.append(subprocess.Popen(
                    [GODOT, "--headless", "--path", str(project), *options,
                     "res://tests/first_boss_pace_probe.tscn", "--", *args],
                    stdout=log, stderr=subprocess.STDOUT))
            if role == "host":
                time.sleep(.4)
        codes = [p.wait(timeout=205) for p in processes]
    except subprocess.TimeoutExpired:
        pass
    finally:
        for p in processes:
            if p.poll() is None:
                p.terminate()
                p.wait(timeout=6)
    rows = []
    for role, path in paths.items():
        raw = path.read_text().splitlines()
        data = next((json.loads(line.removeprefix("[GROWTH] end ")) for line in raw
                     if line.startswith("[GROWTH] end ")), {})
        summary = next((line for line in raw if "SUMMARY pass=" in line), "")
        ok = bool(data) and "failed=0" in summary and codes == [0] * len(roles)
        ok &= not any(line.startswith(("ERROR:", "SCRIPT ERROR")) for line in raw)
        rows.append(dict(variant=variant, case=case, role=role, seed=seed, ok=ok, **data))
        print(variant, case, role, summary, data.get("request"), data.get("entry"),
              data.get("hull_hit"), flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--variant", action="append", choices=("A", "D", "B", "C"))
    parser.add_argument("--case", action="append", choices=tuple(CASES))
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--port", type=int, default=25000)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    variants = args.variant or ["A", "D", "B", "C"]
    cases = args.case or CASES
    with tempfile.TemporaryDirectory(prefix="first-boss-pace-") as tmp:
        roots = {tag: ROOT if tag == "C" else archive(Path(tmp) / tag, tag, out) for tag in variants}
        jobs = [(tag, roots[tag], case, out, args.port + index)
                for index, (case, tag) in enumerate((c, t) for c in cases for t in variants)]
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = [row for batch in pool.map(run, jobs) for row in batch]
    (out / "samples.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return int(not all(row["ok"] for row in results))


if __name__ == "__main__":
    raise SystemExit(main())
