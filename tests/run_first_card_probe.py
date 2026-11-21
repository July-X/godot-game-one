"""Compare the fixed first-card replays and run the director and input gates."""
from concurrent.futures import ThreadPoolExecutor
import csv
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PILOTS = [
    ("pierce", "column"), ("splash", "cluster"),
    ("graze_focus", "edge"), ("power", "center"),
    ("power", "column"), ("power", "cluster"),
    ("power", "edge"), ("graze_focus", "center"),
]


def run(scene, args, log):
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--fixed-fps", "60",
           "--path", str(ROOT), f"res://tests/{scene}.tscn", "--", *args]
    result = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=180)
    log.write_text(result.stdout, encoding="utf-8")
    lines = result.stdout.splitlines()
    verdict = [line for line in lines if line.startswith(("[TRIAL] VERDICT", "[TIMING] verdict", "[WINDOW] SUMMARY"))]
    if result.returncode or len(verdict) != 1 or any("SCRIPT ERROR" in line or line.startswith("ERROR:") for line in lines):
        raise SystemExit(f"{log}: exit={result.returncode}\n{result.stdout}")
    print(log.stem, verdict[0])
    return lines


def events(lines):
    return [json.loads(line.removeprefix("[TRIAL_EVENT] ")) for line in lines
            if line.startswith("[TRIAL_EVENT] ")]


def compare_wave(directory, pilots, extra):
    directory.mkdir(parents=True, exist_ok=True)
    births = None
    paths = {}
    hint_folder = directory / "hint"
    hint_folder.mkdir(exist_ok=True)
    for card, route in pilots:
        name = f"{card}-{route}.log"
        args = [card, route, "--trial-log", *extra]
        a = run("first_card_wave_probe", args, directory / name)
        b = run("first_card_wave_probe", [*args, "--trial-hint"], hint_folder / name)
        trace = [line for line in a if line.startswith("[TRACE]")]
        path = [line for line in a if line.startswith("[PATH]")]
        if len(trace) != 15 or (births is not None and trace != births):
            raise SystemExit(f"{name}: enemy or fan trace differs")
        if len(path) != 1 or paths.setdefault(route, path) != path:
            raise SystemExit(f"{name}: control-card trajectory differs")
        births = trace
        for tag in ["[TRACE]", "[PATH]", "[FRAME]", "[TRIAL] card="]:
            left = [line for line in a if line.startswith(tag)]
            right = [line for line in b if line.startswith(tag)]
            if left != right or (tag == "[FRAME]" and len(left) != 550):
                raise SystemExit(f"{name}: A/B differ in {tag}")
        a_events, b_events = events(a), events(b)
        starts_ends = [(e["event"], e["tick"]) for e in b_events if e["event"].startswith("hint_")]
        window = {"pierce": (1, 180), "splash": (1, 180), "graze_focus": (188, 362)}.get(card)
        expected_hints = [("hint_start", window[0]), ("hint_end", window[1])] if window else []
        observed = [e["event"] for e in a_events]
        expected_events = ["choice", "first_result", "slice_end"] if (card, route) in PILOTS[:3] else ["choice", "slice_end"]
        if observed != expected_events or a_events[0]["source"] != "key" or starts_ends != expected_hints:
            raise SystemExit(f"{name}: incorrect choice, hint window or style result")
        gameplay_a = [{k: v for k, v in e.items() if k != "variant"} for e in a_events]
        gameplay_b = [{k: v for k, v in e.items() if k != "variant"} for e in b_events if not e["event"].startswith("hint_")]
        if gameplay_a != gameplay_b:
            raise SystemExit(f"{name}: gameplay event timing or health differs")
    print(f"[A/B] {len(pilots)} pairs, {550 * len(pilots)} matching frames, {15 * len(pilots)} matching births")


def compare(directory):
    compare_wave(directory, PILOTS, [])
    compare_wave(directory / "wide", PILOTS[:4], ["--wide"])
    for scene in ["first_card_timing", "first_card_run_probe"]:
        for mode in ["input", "timeout"]:
            prefix = directory / f"{scene}-{mode}"
            # 即使带 B 参数，普通战斗也没有试飞节点或试飞日志。
            flags = ["--trial-hint", "--trial-log"] if scene == "first_card_timing" else ["--trial-log"]
            lines = run(scene, [mode, str(prefix.with_suffix(".csv")), *flags], prefix.with_suffix(".log"))
            if scene == "first_card_timing" and events(lines):
                raise SystemExit("ordinary battle produced trial events")
    for mode in ["input", "timeout"]:
        prefix = directory / "hint" / f"first_card_run_probe-{mode}"
        lines = run("first_card_run_probe", [mode, str(prefix.with_suffix(".csv")), "--trial-hint", "--trial-log"],
                    prefix.with_suffix(".log"))
        choices = [e for e in events(lines) if e["event"] == "choice"]
        if len(choices) != 1 or choices[0]["source"] != ("timeout" if mode == "timeout" else "key"):
            raise SystemExit(f"{prefix}: incorrect first-card source")
    for label, extra in [("16x9", []), ("20x9", ["--wide"])]:
        run("first_card_controls_probe", ["--trial-hint", "--trial-log", "--from-draft", *extra],
            directory / f"controls-{label}.log")
    run("first_card_entry_probe", [], directory / "entry.log")


def compare_columns(directory):
    directory.mkdir(parents=True, exist_ok=True)
    summaries = []
    with (directory / "paths.csv").open("w", newline="", encoding="utf-8") as output:
        paths = csv.writer(output)
        paths.writerow(["view", "route", "tick", "x", "y"])
        for view, extra in [("16x9", []), ("20x9", ["--wide"])]:
            births = None
            for route in ["column", "column-left", "column-right", "center"]:
                trajectory = None
                for card in ["pierce", "power"]:
                    log = directory / f"{view}-{route}-{card}.log"
                    lines = run("first_card_wave_probe", [card, route, "--column-evidence", *extra], log)
                    trace = [line for line in lines if line.startswith("[TRACE]")]
                    if len(trace) != 15 or (births is not None and trace != births):
                        raise SystemExit(f"{log}: fixed births changed")
                    births = trace
                    path = next(json.loads(line.removeprefix("[COLUMN_PATH] ")) for line in lines
                                if line.startswith("[COLUMN_PATH] "))
                    ticks = [int(line.split()[1]) for line in lines if line.startswith("[FRAME] ")]
                    samples = list(zip(ticks[:-1], path))
                    if len(ticks) != 550 or len(path) != len(ticks) - 1 or (trajectory is not None and samples != trajectory):
                        raise SystemExit(f"{log}: paired flight path differs")
                    if trajectory is None:
                        paths.writerows([view, route, tick, *point] for tick, point in samples)
                    trajectory = samples

                    stats = next(json.loads(line.removeprefix("[COLUMN] ")) for line in lines
                                 if line.startswith("[COLUMN] "))
                    contacts = stats["pair"].get("contacts", [])
                    expected_pair = route != "center" and card == "pierce"
                    if bool(contacts) != expected_pair or (contacts and len({hit["order"] for hit in contacts}) != 2):
                        raise SystemExit(f"{log}: unexpected result for the same shot on two left targets")
                    if stats["hp_lost"] or (route == "center" and (
                            stats["left_contacts"] or path[0][1] - path[-1][1] < 100)):
                        raise SystemExit(f"{log}: flight or safe middle path failed")
                    expected_kills = 0 if route == "center" else 3
                    if stats["left_kills"] != expected_kills:
                        raise SystemExit(f"{log}: unexpected left squad kill count")
                    summaries.append(dict(stats, view=view))
    (directory / "columns.json").write_text(json.dumps(summaries, indent=2), encoding="utf-8")
    print(f"[COLUMN] {len(summaries) // 2} paired paths, 549 position samples per flight")


def window_data(log, args):
    lines = run("offense_window_probe", args, log)
    return next(json.loads(line.removeprefix("[WINDOW_DATA] ")) for line in lines
                if line.startswith("[WINDOW_DATA] "))


def check_window_flight(runs, label):
    first = runs[0]
    if any(row[key] != first[key] for row in runs[1:] for key in ("path", "births", "samples")):
        raise SystemExit(f"{label}: paired trajectories or births differ")


def compare_offense_window(directory):
    directory.mkdir(parents=True, exist_ok=True)
    runs = []
    for view, aspect in [("16x9", []), ("20x9", ["--wide"])]:
        for route, input_flags in [("rush", []), ("late", []), ("center", []), ("rush", ["--touch-flight"])]:
            label = "touch" if input_flags else route
            pair = []
            for card in ["pierce", "power"]:
                log = directory / f"{view}-{label}-{card}.log"
                data = window_data(log, [card, route, *aspect, *input_flags, "--legacy"])
                pair.append(data)
                runs.append(dict(data, input="touch" if input_flags else "mouse"))
            check_window_flight(pair, f"{view} {label}")
        run("offense_window_probe", ["--entry", *aspect], directory / f"{view}-entry.log")
    (directory / "windows.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
    print(f"[WINDOW] {len(runs) // 2} matched pairs")


def compare_offense_window_v2(directory):
    directory.mkdir(parents=True, exist_ok=True)
    inputs = [(width, delay, offset) for width in (1280, 1600)
              for delay in (0, 12, 18, 24, 36) for offset in (-12, 0, 12)]
    cards = ("pierce", "power")
    versions = ("legacy", "revised")

    def replay(case):
        width, delay, offset, version, card = case
        name = f"{width}-{delay}-{offset:+d}-{version}-{card}"
        args = [card, "rush", "--touch-flight", "--first-wave", f"--delay={delay}", f"--offset={offset}"]
        if width == 1600:
            args.append("--wide")
        if version == "legacy":
            args.append("--legacy")
        return window_data(directory / f"{name}.log", args)

    def first_fan(row):
        return [len(lane) for lane in row["fans"].get(str(row["fire_ticks"][0]), [[], []])]

    cases = [(*flight, version, card) for flight in inputs for version in versions for card in cards]
    with ThreadPoolExecutor(max_workers=4) as workers:
        results = dict(zip(cases, workers.map(replay, cases)))
    (directory / "matrix.json").write_text(json.dumps(list(results.values()), indent=2), encoding="utf-8")

    for width, delay, offset in inputs:
        flight = (width, delay, offset)
        paired = [results[(*flight, version, card)] for version in versions for card in cards]
        check_window_flight(paired, flight)
        for row in paired:
            fire, charge_start = (166, 118) if row["version"] == "legacy" else (188, 96)
            if row["fire_ticks"] != [fire, 244] or row["charge_starts"].get(str(fire)) != charge_start:
                raise SystemExit(f"{flight}: opening charge or first fan time changed")
        pierce, power = map(first_fan, paired[2:])
        if (delay == 24 and (pierce, power) != ([0, 3], [3, 3])
                or delay == 36 and (pierce, power) != ([3, 3], [3, 3])):
            raise SystemExit(f"{flight}: changed first-fan result on the delayed paired routes")
    for version in versions:
        totals = [sum(first_fan(results[(*flight, version, card)]) == [0, 3] for flight in inputs)
                  for card in cards]
        print(f"[WINDOW] {version} first-fan interruptions: pierce={totals[0]}/30 power={totals[1]}/30")

    full_runs = []
    for width in (1280, 1600):
        aspect = ["--wide"] if width == 1600 else []
        for route in ("rush", "center"):
            pair = [window_data(directory / f"{width}-full-{route}-{card}.log",
                                [card, route, "--touch-flight", "--delay=24", *aspect])
                    for card in cards]
            check_window_flight(pair, (width, route))
            if route == "center" and any(first_fan(row) != [3, 3] or row["interruptions"] for row in pair):
                raise SystemExit(f"{width}: center transit interfered with a volley")
            full_runs.extend(pair)
    (directory / "full.json").write_text(json.dumps(full_runs, indent=2), encoding="utf-8")
    print(f"[WINDOW] {len(results)} opening replays, {len(full_runs)} full flights")


if __name__ == "__main__":
    if len(sys.argv) == 2:
        compare(Path(sys.argv[1]).resolve())
    elif len(sys.argv) == 1:
        with tempfile.TemporaryDirectory() as scratch:
            compare(Path(scratch))
    elif len(sys.argv) == 3 and sys.argv[2] == "--column":
        compare_columns(Path(sys.argv[1]).resolve())
    elif len(sys.argv) == 3 and sys.argv[2] == "--offense-window":
        compare_offense_window(Path(sys.argv[1]).resolve())
    elif len(sys.argv) == 3 and sys.argv[2] == "--offense-window-v2":
        compare_offense_window_v2(Path(sys.argv[1]).resolve())
    else:
        raise SystemExit("usage: python3 tests/run_first_card_probe.py [log-directory [--column|--offense-window|--offense-window-v2]]")
