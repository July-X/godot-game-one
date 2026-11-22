"""Capture one joystick flight per route and replay it in both elite trial variants."""
from concurrent.futures import ThreadPoolExecutor
from itertools import product
import csv
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEWS = (1280, 1600)
ROUTES = ("press", "dodge", "early", "late", "hold")
START = 3240
CONTACT_RANGE = 208.0
OPEN = .22
CLOSE = 1.30


def run(width, name, directory, *args):
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--fixed-fps", "60",
           "--path", str(ROOT), "--quit-after", "1200", "res://tests/elite_close_trial_probe.tscn", "--", *args]
    if width == 1600:
        cmd.append("--wide")
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=90)
    log = directory / f"{width}-{name}.log"
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    if (result.returncode or "[CLOSE] SUMMARY failed=0" not in result.stdout.splitlines()
            or any(line.startswith(("ERROR:", "SCRIPT ERROR:"))
                   for line in (result.stdout + result.stderr).splitlines())):
        raise SystemExit(f"{log}: exit {result.returncode}")
    data = [line.removeprefix("[CLOSE_DATA] ") for line in result.stdout.splitlines() if line.startswith("[CLOSE_DATA] ")]
    return json.loads(data[0]) if data else None


def check(condition, width, route, reason):
    if not condition:
        raise SystemExit(f"{width} {route}: {reason}")


def pair(width, route, folder):
    a = run(width, f"{route}-a", folder, route)
    flight = folder / f"{width}-{route}-flight.json"
    flight.write_text(json.dumps(a["flight"]), encoding="utf-8")
    b = run(width, f"{route}-b", folder, route, "--close-b", f"--flight={flight}")
    check(a["mode"] == "A" and b["mode"] == "B" and a["seed"] == b["seed"] == 90220,
          width, route, "variant or seed")
    check(a["flight"] == b["flight"] and len(a["flight"]) == 1080
          and [f[:3] for f in a["frames"]] == [f[:3] for f in b["frames"]],
          width, route, "paired positions or inputs differ")
    first_gain = b["bonus"][0][0] if b["bonus"] else START + 1080
    check(all(next(f[5:7] for f in row["frames"] if f[5] > 0) == [125, 50] for row in (a, b)),
          width, route, "original elite HP or shield changed")
    check(a["break"] == b["break"] and a["fans"] == b["fans"] and a["interruptions"] == b["interruptions"]
          and [f for f in a["births"] if f[1] < first_gain] == [f for f in b["births"] if f[1] < first_gain]
          and [f for f in a["frames"] if f[0] < first_gain] == [f for f in b["frames"] if f[0] < first_gain]
          and [f for f in a["elite_shots"] if f[0] < first_gain] == [f for f in b["elite_shots"] if f[0] < first_gain],
          width, route, "elite or escorts diverge before the first bonus")
    check(not a["bonus"] and (bool(b["bonus"]) == (route in ("press", "hold"))),
          width, route, "unexpected bonus")
    hits = {h[7]: h for h in b["contacts"]}
    check(len({hit[1] for hit in b["bonus"]}) == len(b["bonus"])
          and all(shot in hits and hits[shot][0] == tick and hits[shot][5] <= CONTACT_RANGE
                  and OPEN <= hits[shot][6] < CLOSE and 0 < damage <= 5 for tick, shot, damage in b["bonus"]),
          width, route, "bonus without distinct close-range main cannon contacts in the window")
    close_frame = b["break"] + round(CLOSE * 60) + 1
    near_hits = [h for h in b["contacts"] if h[5] <= CONTACT_RANGE]
    if route != "hold":
        check(not a["losses"] and not b["losses"] and not a["enemy_contacts"] and not b["enemy_contacts"],
              width, route, "retreat flight was hit")
    if route != "dodge":
        check(len(a["interruptions"]) == 1 and a["interruptions"][0][0] == "3300-cluster-rear"
              and "3300-cluster-rear" not in a["fans"], width, route, "escort did not actually cancel its fan")
    if route == "press":
        check(b["defeat"] >= 0 and (a["defeat"] < 0 or b["defeat"] <= a["defeat"] - 45),
              width, route, "bonus did not meaningfully accelerate the kill")
        a_hp, b_hp = [row["frames"][close_frame - START][5] for row in (a, b)]
        check(a_hp - b_hp >= 25, width, route, "HP at window close did not separate")
    elif route == "hold":
        check(any(t > close_frame and layer == "hull" and amount > 0 for t, layer, amount in b["losses"]),
              width, route, "greedy hold did not take real hull damage after the window")
    elif route == "early":
        check(any(h[6] < OPEN for h in near_hits), width, route, "no early close hit observed")
    elif route == "late":
        late = [h for h in near_hits if h[6] >= CLOSE]
        check(late and any(t > late[0][0] and hp > 0 and (x - ex) ** 2 + (y - ey) ** 2 > (CONTACT_RANGE + 40) ** 2
                           for t, x, y, ex, ey, hp, _ in b["frames"]),
              width, route, "no late contact followed by retreat past a live elite")
    else:
        check(a["break"] < 0 and len(a["fans"]["3300-cluster-rear"]) == 3,
              width, route, "evasion did not leave the escort and elite intact")
    print(width, route, "pass", flush=True)
    return a, b


def main(directory):
    directory.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as workers:
        cases = list(workers.map(lambda key: pair(*key, directory), product(VIEWS, ROUTES)))
    for width, mode in product(VIEWS, ("a", "b")):
        args = ("--retry", "--close-b") if mode == "b" else ("--retry",)
        run(width, f"retry-{mode}", directory, *args)
    rows = [row for case in cases for row in case]
    (directory / "replays.json").write_text(json.dumps(rows), encoding="utf-8")
    with (directory / "summary.csv").open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(["view", "route", "mode", "shield_open_tick", "bonus_contacts", "bonus_damage", "defeat_seconds",
                         "elite_hp_at_end", "hull_lost", "shield_lost"])
        for row in rows:
            hull = sum(n for _, layer, n in row["losses"] if layer == "hull")
            shield = sum(n for _, layer, n in row["losses"] if layer == "shield")
            defeat = round((row["defeat"] - START) / 60, 3) if row["defeat"] >= 0 else ""
            writer.writerow([row["view"], row["route"], row["mode"], row["break"], len(row["bonus"]),
                             sum(hit[2] for hit in row["bonus"]), defeat, row["remaining_hp"], hull, shield])
    print("[CLOSE] 10 matched pairs, 4 touch retries")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tests/run_elite_close_trial_probe.py <log-directory>")
    main(Path(sys.argv[1]).resolve())
