"""Run the real Godot lobby with two loopback peers and keep per-role timings."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def traces(log, event, tag="ENTRY"):
    prefix = f"[{tag}] {event} "
    return [json.loads(line[len(prefix):]) for line in log.splitlines() if line.startswith(prefix)]


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
                    command + [role, str(port), mode, "device-a" if device_a else "device-b",
                               "--entry-shot-trace", *extra],
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
        assert not any(line.startswith("ERROR:") and "resources still in use at exit" not in line
                       for line in log.splitlines()), name
    if "entry-timeout" in extra:
        return {"case": name, "timeout_and_retry": True}
    host, client = logs
    host_ready = trace(host, "scene")["wall_ms"]
    guest_ready = trace(client, "scene")["wall_ms"]
    guest_moved = trace(client, "pilot_moved")["wall_ms"]
    first_bullet = trace(host, "authority_bullet")["wall_ms"]
    authoritative_move = trace(host, "authority_move")
    host_confirmed = trace(host, "active_on_host")["wall_ms"]
    guest_movement = trace(client, "pilot_moved")
    assert authoritative_move["slot"] == guest_movement["slot"] == trace(host, "authority_bullet")["slot"], name
    pos = [row for row in traces(host, "position_applied", "ENTRY_SHOT")
           if row["slot"] == authoritative_move["slot"] and
           abs(row["x"] - authoritative_move["spawn_x"]) > 8 and row["wall_ms"] <= authoritative_move["wall_ms"]]
    assert pos, name
    for stage_log, event in ((client, "position_sent"), (host, "position_rpc")):
        assert any(row["slot"] == pos[0]["slot"] and row["status"] == 0 and
                   (row["x"], row["y"]) == (pos[0]["x"], pos[0]["y"])
                   for row in traces(stage_log, event, "ENTRY_SHOT")), name
    assert max(guest_moved, first_bullet, host_confirmed) - min(host_ready, guest_ready) <= 1000, name
    followups = []
    if mode == "remix":
        initial_round = trace(host, "scene")["round"]
        first = [row for row in traces(client, "flush_initial_reliable", "ENTRY_SHOT") if row["round"] == initial_round]
        assert len(first) == 1 and first[0]["status"] == 0 and first[0]["ready"], name
        received = [row for row in traces(host, "rpc_reliable", "ENTRY_SHOT") if row["round"] == initial_round]
        assert len(received) == 1 and received[0]["slot"] == first[0]["slot"], name
        assert first[0]["wall_ms"] <= received[0]["wall_ms"] <= first_bullet, name
        ordered = traces(host, "rpc_ordered", "ENTRY_SHOT")
        spawned = [row for row in traces(host, "authority_batch", "ENTRY_SHOT") if row["round"] == initial_round]
        assert spawned[0]["batch"] == first[0]["batch"] == received[0]["batch"] and spawned[0]["reliable"], name
        following = [row for row in spawned if not row["reliable"]]
        sent = traces(client, "flush_ordered", "ENTRY_SHOT")
        assert len(following) >= 2 and len({row["batch"] for row in following[:2]}) == 2, name
        assert all(any(row["batch"] == batch["batch"] for row in sent) and
                   any(row["batch"] == batch["batch"] for row in ordered) for batch in following[:2]), name
        followups = trace(host, "followups")["after_first_ms"][:2]
        assert len(followups) == 2 and followups[1] <= 1300, name
    return {"case": name, "host_device": "4:3" if swap else "20:9",
            "scene_gap_ms": guest_ready - host_ready,
            "guest_move_ms": guest_moved - guest_ready,
            "first_authority_bullet_ms": first_bullet - guest_ready,
            "authority_move_ms": authoritative_move["wall_ms"] - guest_ready,
            "authority_move_and_shot_ms": host_confirmed - min(host_ready, guest_ready),
            "followups_after_first_ms": followups}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--remix-runs", type=int, default=6)
    parser.add_argument("--start-port", type=int, default=19910)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cases = [(f"remix-{i + 1}", "remix", i % 2 != 0, ()) for i in range(args.remix_runs)]
    cases += [("rift", "rift", True, ()), ("normal", "normal", False, ()),
              ("remix-recovery", "remix", True, ("recover",)),
              ("remix-timeout", "remix", False, ("entry-timeout",))]
    results = []
    failed = 0
    for index, (name, mode, swap, extra) in enumerate(cases):
        try:
            row = run_pair(output, name, args.start_port + index, mode, swap, *extra)
        except (AssertionError, StopIteration, subprocess.TimeoutExpired) as error:
            failed += 1
            row = {"case": name, "failed": True, "detail": str(error)}
        print(json.dumps(row, ensure_ascii=False), flush=True)
        results.append(row)
    (output / "timings.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(failed != 0)


if __name__ == "__main__":
    sys.exit(main())
