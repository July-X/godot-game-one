"""Run the real Godot lobby with two loopback peers and keep per-role timings."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def trace(log, event):
    prefix = f"[ENTRY] {event} "
    return json.loads(next(line[len(prefix):] for line in log.splitlines() if line.startswith(prefix)))


def run_pair(output, name, port, mode, swap, *extra):
    command = [os.getenv("GODOT", "godot"), "--headless", "--path", ".",
               "res://tests/lobby_start_probe.tscn", "--"]
    jobs = []
    try:
        for role in ("host", "client"):
            device_a = (role == "host") != swap
            with (output / f"{name}-{role}.log").open("w", encoding="utf-8") as log:
                jobs.append(subprocess.Popen(
                    command + [role, str(port), mode, "device-a" if device_a else "device-b", *extra],
                    stdout=log, stderr=subprocess.STDOUT))
            if role == "host":
                time.sleep(.4)
        codes = [job.wait(timeout=24) for job in jobs]
    finally:
        for job in jobs:
            if job.poll() is None:
                job.terminate()
                job.wait(timeout=5)

    logs = [(output / f"{name}-{role}.log").read_text(encoding="utf-8")
            for role in ("host", "client")]
    for code, log in zip(codes, logs):
        assert code == 0 and "failed=0" in log, name
        assert not any(word in log for word in ("SCRIPT ERROR", "Node not found",
                                               "未找到本地玩家", "仍未找到")), name
    if "entry-timeout" in extra:
        return {"case": name, "timeout_and_retry": True}
    host, client = logs
    host_ready = trace(host, "scene")["wall_ms"]
    guest_ready = trace(client, "scene")["wall_ms"]
    guest_moved = trace(client, "pilot_moved")["wall_ms"]
    first_bullet = trace(host, "authority_bullet")["wall_ms"]
    host_confirmed = trace(host, "active_on_host")["wall_ms"]
    assert max(guest_moved, first_bullet, host_confirmed) - min(host_ready, guest_ready) <= 1000, name
    return {"case": name, "host_device": "4:3" if swap else "20:9",
            "scene_gap_ms": guest_ready - host_ready,
            "guest_move_ms": guest_moved - guest_ready,
            "first_authority_bullet_ms": first_bullet - guest_ready,
            "authority_move_and_shot_ms": host_confirmed - host_ready}


def main():
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    cases = [(f"remix-{i + 1}", "remix", i % 2 != 0, ()) for i in range(6)]
    cases += [("rift", "rift", True, ()), ("normal", "normal", False, ()),
              ("remix-recovery", "remix", True, ("recover",)),
              ("remix-timeout", "remix", False, ("entry-timeout",))]
    results = []
    for index, (name, mode, swap, extra) in enumerate(cases):
        row = run_pair(output, name, 19910 + index, mode, swap, *extra)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        results.append(row)
    (output / "timings.json").write_text(json.dumps(results, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
