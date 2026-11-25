"""Replay two Rift Route waves through the real joystick and projectile paths."""
import json
import os
from pathlib import Path
import subprocess
import sys

PROFILES = [
    ("pierce", "column"), ("pierce", "wing"),
    ("splash", "cluster"), ("splash", "column"),
    ("power", "wing"), ("power", "column"), ("power", "dodge"),
]
WAVES = (2190, 2860)
EMITTERS = ("column-rear", "cluster-rear", "wing")


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


def check_candidate(rows):
    by_route = {(r["card"], r["route"]): r for r in rows}
    for tick in WAVES:
        wing = f"{tick}-wing"
        column = f"{tick}-column-rear"
        cluster = f"{tick}-cluster-rear"
        pierce = by_route["pierce", "column"]
        preceding_shots = {
            hit[1] for rank in ("front", "middle")
            for hit in pierce["hits"][f"{tick}-column-{rank}"]
        }
        assert any(h[1] in preceding_shots and h[3] == "pierce" for h in pierce["hits"][column])
        splash = by_route["splash", "cluster"]
        assert any(h[3] == "splash" for h in splash["hits"][cluster])
        assert sum(event[0] == cluster for event in splash["interruptions"]) == 1
        strong = by_route["power", "wing"]["hits"][wing]
        regular = by_route["pierce", "wing"]["hits"][wing]
        assert len(strong) == 1 and strong[0][-1] <= 0
        assert regular[0][-1] > 0 and len(regular) >= 2
        for card, route in PROFILES:
            row = by_route[card, route]
            if route == "dodge":
                assert len(row["fans"][cluster]) == 3
                assert not any(event[0] == cluster for event in row["interruptions"])
                assert sum(len(row["fans"].get(f"{tick}-{name}", [])) for name in EMITTERS) >= 6
                continue
            aimed = f"{tick}-" + (route if route == "wing" else f"{route}-rear")
            assert aimed in row["deaths"] and aimed not in row["fans"], (card, route, aimed)
            feedback = sum(event[0] == aimed for event in row["interruptions"])
            assert feedback == int(aimed in row["charges"]), (card, route, aimed, feedback)
            assert any(f"{tick}-{name}" in row["fans"] for name in EMITTERS)
    assert all(not any(loss[1] == "hull" for loss in row["losses"]) for row in rows)


def main(out, baseline):
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for wide in (False, True):
        pair = [run(out, card, route, wide) for card, route in PROFILES]
        assert len({json.dumps(d["births"]) for d in pair}) == 1
        if not baseline:
            check_candidate(pair)
        for row in pair:
            fans = [[len(row["fans"].get(f"{tick}-{name}", [])) for name in EMITTERS] for tick in WAVES]
            print(row["view"], row["card"], row["route"], fans)
        rows.extend(pair)
    (out / "replays.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print("[RIFT BUILD] PASS: 14 fixed-touch replays, two waves per replay")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--baseline"):
        raise SystemExit("usage: python3 tests/run_rift_build_probe.py <log-directory> [--baseline]")
    main(Path(sys.argv[1]).resolve(), "--baseline" in sys.argv[2:])
