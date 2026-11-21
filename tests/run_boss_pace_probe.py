"""Collect normal solo runs to first Boss defeat, player death or the observation limit."""
import csv
import json
import math
import os
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

from run_first_card_probe import ROOT


def collect(directory, realtime=False):
    directory.mkdir(parents=True, exist_ok=True)
    paths = [("input", "anchor"), ("timeout", "anchor"), ("input", "evade"),
             ("input", "assisted"), ("timeout", "assisted")]
    cases = [(seed, mode, pilot, 1) for seed in (1121, 1122, 1123) for mode, pilot in paths]
    cases.append((1121, "input", "assisted", 2))
    if realtime:
        cases = [(1121, "input", pilot, 1) for pilot in ("anchor", "assisted")]
    error_runs = 0
    defeats = 0
    with (directory / "samples.csv").open("w", newline="", encoding="utf-8") as output:
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(["seed", "mode", "pilot", "repeat", "event", "tick", "kills", "level", "data"])
        for seed, mode, pilot, repeat in cases:
            name = f"{seed}-{mode}-{pilot}-{repeat}"
            cmd = [os.environ.get("GODOT", "godot"), "--headless", "--max-fps" if realtime else "--fixed-fps",
                   "60", "--path", str(ROOT), "res://tests/boss_pace_probe.tscn", "--", mode,
                   str(directory / (name + ".births.csv")), str(seed), pilot]
            started = time.monotonic()
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, timeout=660 if realtime else 180)
            (directory / (name + ".log")).write_text(result.stdout, encoding="utf-8")
            lines = result.stdout.splitlines()
            events = [json.loads(line[7:]) for line in lines if line.startswith("[PACE] ")]
            # Keep every observation, including clean death signals followed by an engine error.
            errors = Counter(line.strip() for line in lines if line.startswith(("ERROR:", "SCRIPT ERROR:")))
            error_runs += bool(errors or result.returncode)
            validate(events, mode, pilot)
            end = next(row for row in events if row["event"] == "end")
            defeats += end["data"]["outcome"] == "boss_defeat"
            status = {"godot_exit": result.returncode, "errors": errors, "wall_s": round(time.monotonic() - started, 2)}
            events.append(dict(end, event="process_exit", data=status))
            for row in events:
                writer.writerow([seed, mode, pilot, repeat, row["event"], row["tick"], row["kills"],
                                 row["level"], json.dumps(row["data"], separators=(",", ":"), sort_keys=True)])
            output.flush()
            print(name, end["data"]["outcome"], f'tick={end["tick"]}', f'errors={sum(errors.values())}', flush=True)
    if not defeats:
        raise SystemExit("No real boss_died signal in the sample")
    if error_runs:
        raise SystemExit(f"Collected {len(cases)} observations; engine gate failed in {error_runs} runs (see samples.csv)")


def validate(events, mode, pilot):
    by_kind = {}
    for row in events:
        by_kind.setdefault(row["event"], []).append(row)
    end = by_kind["end"][0]
    data = end["data"]
    assert len(by_kind["end"]) == 1 and by_kind["verdict"][0]["data"]["detail"] == "pass=true"
    assert data["assisted"] == (pilot == "assisted")
    assert math.isfinite(data["max_displacement"])
    offer = None
    for event in events:
        if event["event"] == "offer":
            offer = event
        elif event["event"] == "choice":
            card, index, reason = event["data"]["detail"].split()
            assert offer["data"]["detail"].split(",")[int(index.split("=")[1])] == card
            assert reason == ("reason=script_key" if mode == "input" else "reason=timeout")
            offer = None
    if data["outcome"] == "player_dead":
        assert data["hp"] == 0
    elif data["outcome"] == "observation_limit":
        assert end["tick"] >= 36000 and data["hp"] > 0
    else:
        assert data["outcome"] == "boss_defeat"
        cause = by_kind["boss_defeat"][0]["data"]["cause"]
        if data["boss_remaining_hp"] == 0:
            assert cause == "hp_zero"
        else:
            assert cause == "screen_bomb" and by_kind["bomb_pickup"][-1]["tick"] <= end["tick"]
        for kind in ("elite_defeat", "boss_attackable_in_view", "boss_first_damage", "choice"):
            assert by_kind[kind][0]["tick"] <= end["tick"], kind
    if "boss_entry" in by_kind:
        entry = by_kind["boss_entry"][0]["tick"]
        assert abs(entry - by_kind["boss_request"][0]["tick"] - data["wait_elite"] - data["wait_other"]) <= 1
        assert abs(end["tick"] - entry - data["open"] - data["shield"] - data["outside"]) <= 1
        assert 0 <= data["boss_remaining_hp"] <= data["boss_start_hp"]
    if "next_wave_build_used" in by_kind:
        assert by_kind["build_used"][0]["tick"] <= by_kind["next_wave_build_used"][0]["tick"]
        assert by_kind["next_wave_contact"][0]["tick"] <= by_kind["next_wave_build_used"][0]["tick"]
    if "next_wave_contact" in by_kind:
        assert by_kind["next_wave"][0]["tick"] <= by_kind["next_wave_contact"][0]["tick"]


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--realtime"):
        raise SystemExit("Usage: python3 tests/run_boss_pace_probe.py output-directory [--realtime]")
    collect(Path(sys.argv[1]).resolve(), "--realtime" in sys.argv)
