"""Replay the opening trial through production movement, shots, and card selection."""
from concurrent.futures import ThreadPoolExecutor
import csv
from itertools import product
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VIEWS = (1280, 1600)
ROLES = {"column": "column-rear", "cluster": "cluster-rear", "wing": "wing"}
STYLES = {"column": "pierce", "cluster": "splash", "wing": "power"}
BUILD = 1290
FINALE = 3300


def run(folder, width, name, *args):
    log = folder / f"{width}-{name}.log"
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--fixed-fps", "60",
           "--path", str(ROOT), "--quit-after", "6400", "res://tests/opening_trial_probe.tscn", "--", *args]
    if width == 1600:
        cmd.append("--wide")
    result = subprocess.run(cmd, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log.write_text(result.stdout, encoding="utf-8")
    lines = result.stdout.splitlines()
    if (result.returncode or "[OPENING] SUMMARY failed=0" not in lines
            or any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in lines)):
        raise SystemExit(f"{log}: exit={result.returncode}\n{result.stdout}")
    print(log.stem, "passed", flush=True)
    data = [line.removeprefix("[OPENING_DATA] ") for line in lines if line.startswith("[OPENING_DATA] ")]
    return json.loads(data[0]) if data else None


def check(condition, context):
    if not condition:
        raise SystemExit(f"Opening acceptance failed: {context}")


def fans(row, role, tick=BUILD):
    return len(row["fans"].get(f"{tick}-{role}", []))


def contacts(row, role, kind):
    return [hit for hit in row["hits"].get(f"{BUILD}-{role}", []) if hit[3] == kind]


def compare_build(cases):
    summary = []
    for width in VIEWS:
        for route in (*ROLES, "dodge"):
            profiles = [cases[width, card, route] for card in STYLES.values()]
            check(all(row["births"] == profiles[0]["births"] and row["position_hash"] == profiles[0]["position_hash"]
                      for row in profiles), (width, route, "paired spawns and trajectory"))
            for row in profiles:
                card = row["card"]
                counts = [fans(row, role) for role in ROLES.values()]
                expected = [0 if route == other and STYLES[other] == card else 3 for other in ROLES]
                check(counts == expected, (width, card, route, counts))
                if route == "dodge":
                    check(not row["enemy_contacts"] and not row["interruptions"] and not row["losses"],
                          (width, card, "evasive flight"))
                hull = sum(n for _, layer, n in row["losses"] if layer == "hull")
                shield = sum(n for _, layer, n in row["losses"] if layer == "shield")
                summary.append([width, route, card, *counts, row["deaths"].get(f"{BUILD}-{ROLES.get(route)}", ""),
                                hull, shield, len(row["enemy_contacts"])])
        pierce = cases[width, "pierce", "column"]
        front = contacts(pierce, "column-front", "direct")[0]
        rear = contacts(pierce, "column-rear", "pierce")[0]
        check(front[1] == rear[1] and front[0] < rear[0] and rear[5] <= 0, (width, "same bolt reached rear"))
        splash = cases[width, "splash", "cluster"]
        group = [contacts(splash, name, kind)[0] for name, kind in (
            ("cluster-front", "direct"), ("cluster-neighbor", "splash"), ("cluster-rear", "splash"))]
        check(len({(hit[0], hit[1]) for hit in group}) == 1 and all(hit[5] <= 0 for hit in group),
              (width, "one shot cleared three real actors"))
        for card, expected in (("power", 1), ("pierce", 2), ("splash", 2)):
            wing = contacts(cases[width, card, "wing"], "wing", "direct")
            check(len(wing) == expected and wing[-1][5] <= 0, (width, card, "wing contact threshold"))
    return summary


def main(folder):
    folder.mkdir(parents=True, exist_ok=True)
    trials = list(product(VIEWS, STYLES.values(), (*ROLES, "dodge")))
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(lambda c: run(folder, c[0], f"{c[1]}-{c[2]}", c[1], c[2], "--first-build"), trials))
    build = dict(zip(trials, rows))
    summary = compare_build(build)
    with (folder / "build.csv").open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(["width", "route", "card", "column_rounds", "cluster_rounds", "wing_rounds",
                         "target_death_tick", "hull_lost", "shield_lost", "enemy_contacts"])
        writer.writerows(summary)
    for width in VIEWS:
        run(folder, width, "entry", "--entry")
        run(folder, width, "timeout", "pierce", "dodge", "--first-build", "--timeout")
        strike = run(folder, width, "practice-strike", "pierce", "column", "--intro")
        dodge = run(folder, width, "practice-dodge", "pierce", "dodge", "--intro")
        check(strike["births"] == dodge["births"] and not strike["choice"] and not dodge["choice"],
              (width, "same base-weapon encounter"))
        check(len(strike["interruptions"]) == 1 and not strike["fans"] and not strike["losses"]
              and not dodge["interruptions"] and fans(dodge, "practice-78", 78) == 3
              and not dodge["enemy_contacts"] and not dodge["losses"], (width, "practice strike / dodge"))
        rows.extend((strike, dodge))
        avoid = run(folder, width, "finale-dodge", "pierce", "dodge")
        press = run(folder, width, "finale-press", "splash", "cluster", "--press-finale")
        forced = run(folder, width, "finale-fan", "power", "cluster", "--press-finale")
        final_fans = [shots for fired, shots in avoid["fans"].items() if int(fired.split("-")[0]) >= FINALE]
        check(avoid["end"] == 5400 and avoid["elite_alive_at_end"] and not avoid["enemy_contacts"] and not avoid["interruptions"]
              and not avoid["losses"] and len(final_fans) == 5
              and all(len(shots) == 3 for shots in final_fans), (width, "complete evasive flight"))
        role = "cluster-rear"
        name = f"{FINALE}-{role}"
        check(press["position_hash"] == forced["position_hash"]
              and fans(press, role, FINALE) == 0 and fans(forced, role, FINALE) == 3
              and any(event[0] == name for event in press["interruptions"])
              and not any(contact[1] == name for contact in press["enemy_contacts"])
              and any(contact[1] == name for contact in forced["enemy_contacts"])
              and any(FINALE + 202 < hit[0] <= FINALE + 310 and hit[5] < 300
                      for hit in press["elite_hits"]), (width, "real interception before close elite fire"))
        rows.extend((avoid, press, forced))
    (folder / "replays.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print("[OPENING] 24 build, 4 practice, 6 finale, 2 entry, 2 timeout")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python3 tests/run_opening_trial_probe.py <log-directory>")
    main(Path(sys.argv[1]).resolve())
