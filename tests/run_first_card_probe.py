"""Compare the fixed first-card replays and run the director and input gates."""
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
    verdict = [line for line in lines if "[TRIAL] VERDICT" in line or "[TIMING] verdict" in line]
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


if __name__ == "__main__":
    if len(sys.argv) == 2:
        compare(Path(sys.argv[1]).resolve())
    elif len(sys.argv) == 1:
        with tempfile.TemporaryDirectory() as scratch:
            compare(Path(scratch))
    else:
        raise SystemExit("usage: python3 tests/run_first_card_probe.py [log-directory]")
