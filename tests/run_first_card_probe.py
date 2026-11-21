"""Run the fixed first-card comparisons and the two live-director paths."""
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


def compare(directory):
    directory.mkdir(parents=True, exist_ok=True)
    expected = None
    paths = {}
    for card, route in PILOTS:
        lines = run("first_card_wave_probe", [card, route], directory / f"{card}-{route}.log")
        trace = [line for line in lines if line.startswith("[TRACE]")]
        path = [line for line in lines if line.startswith("[PATH]")]
        if len(trace) != 15 or (expected is not None and trace != expected):
            raise SystemExit(f"{card}-{route}: enemy or fan trace differs")
        if len(path) != 1 or paths.setdefault(route, path) != path:
            raise SystemExit(f"{card}-{route}: pilot trajectory differs")
        expected = trace
    for scene in ["first_card_timing", "first_card_run_probe"]:
        for mode in ["input", "timeout"]:
            prefix = directory / f"{scene}-{mode}"
            run(scene, [mode, str(prefix.with_suffix(".csv"))], prefix.with_suffix(".log"))


if __name__ == "__main__":
    if len(sys.argv) == 2:
        compare(Path(sys.argv[1]).resolve())
    elif len(sys.argv) == 1:
        with tempfile.TemporaryDirectory() as scratch:
            compare(Path(scratch))
    else:
        raise SystemExit("usage: python3 tests/run_first_card_probe.py [log-directory]")
