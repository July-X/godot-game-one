"""Fixed touch-input replays of the first real build wave in Rift Route."""
import json
import os
from pathlib import Path
import subprocess
import sys


def run(out, card, route, wide):
    args = [os.environ.get("GODOT", "godot"), "--headless", "--fixed-fps", "60",
            "--path", ".", "res://tests/opening_trial_probe.tscn", "--",
            card, route, "--rift-build"]
    if wide:
        args.append("--wide")
    result = subprocess.run(args, capture_output=True, text=True, timeout=40)
    name = f"{'wide' if wide else 'normal'}-{card}-{route}"
    data = result.stdout + result.stderr
    (out / f"{name}.log").write_text(data, encoding="utf-8")
    if result.returncode or "SCRIPT ERROR:" in data or "SUMMARY failed=0" not in data:
        raise AssertionError(f"{name}: probe failed")
    return json.loads(next(x.split(" ", 1)[1] for x in data.splitlines() if x.startswith("[OPENING_DATA] ")))


def first_contacts(row, suffix):
    return row["hits"].get(f"2190-{suffix}", [])


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for wide in (False, True):
        pierce = run(out, "pierce", "column", wide)
        splash = run(out, "splash", "cluster", wide)
        wing = run(out, "power", "wing", wide)
        wing_control = run(out, "pierce", "wing", wide)
        avoid = run(out, "power", "dodge", wide)
        assert len({json.dumps(d["births"]) for d in [pierce, splash, wing, wing_control, avoid]}) == 1
        f = {r[1] for r in first_contacts(pierce, "column-front")}
        assert any(h[1] in f and h[3] == "pierce" for h in first_contacts(pierce, "column-rear"))
        assert any(h[3] == "splash" for h in first_contacts(splash, "cluster-front"))
        assert first_contacts(wing, "wing")[0][-1] <= 0 < first_contacts(wing_control, "wing")[0][-1]
        assert first_contacts(wing, "wing")[0][0] < wing_control["fans"]["2190-wing"][0][0]
        assert not [r for r in avoid["losses"] if r[1] == "hull"]
        rows.extend([pierce, splash, wing, wing_control, avoid])
    (out / "replays.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print("[RIFT BUILD] PASS: 10 fixed-touch replays, two aspect ratios")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tests/run_rift_build_probe.py <log-directory>")
    main(Path(sys.argv[1]).resolve())
