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


def normal_timings(name, swap, host, guest, codes):
    """Keep the timing evidence even when a cold entry misses the gate."""
    def first(log, event, tag="ENTRY"):
        return next(iter(traces(log, event, tag)), {})

    def ms(row):
        return row.get("wall_ms")

    def ready(log):
        value = first(log, "battle_ready_done", "ENTRY_LOAD").get("wall_us")
        return value // 1000 if value is not None else None

    def elapsed(at, origin):
        return at - origin if at is not None and origin is not None else None

    host_ready, guest_ready = ready(host), ready(guest)
    start = ms(first(host, "start_pressed"))
    t0 = min(host_ready, guest_ready) if host_ready is not None and guest_ready is not None else None
    bound = first(guest, "input_bound")
    round_id, slot = bound.get("round"), bound.get("slot")

    def packets(log, event):
        return [row for row in traces(log, event, "ENTRY_SHOT") if row["round"] == round_id]

    fire = next(iter(packets(guest, "auto_fire")), {})
    queued = next(iter(packets(guest, "queued")), {})
    ordered = packets(guest, "flush_ordered")
    reliable = packets(guest, "flush_initial_reliable")
    sent = sorted(ordered + reliable, key=lambda row: row["wall_ms"])
    incoming = packets(host, "rpc_ordered") + packets(host, "rpc_reliable")
    spawned = packets(host, "authority_batch")
    guest_move = first(guest, "pilot_moved")
    host_move = first(host, "authority_move")
    host_bullet = first(host, "authority_bullet")
    local_visual = first(guest, "guest_visual_bullet")
    issues = []
    if codes != [0, 0]:
        issues.append("probe verdict")
    if slot is None or any(row.get("slot") != slot for row in (fire, queued, guest_move, host_move, host_bullet)):
        issues.append("missing or wrong stable slot")
    if any(row["slot"] != slot for row in spawned + sent):
        issues.append("wrong batch slot")
    if len(spawned) < 3 or len({row["batch"] for row in spawned[:3]}) != 3:
        issues.append("first and two distinct followups")
    if any(sum(row["batch"] == volley["batch"] for row in incoming) != 1
           or sum(row["batch"] == volley["batch"] and row["status"] == 0 for row in sent) != 1
           or sum(row["batch"] == volley["batch"] for row in spawned) != 1 for volley in spawned[:3]):
        issues.append("batch correlation or duplication")
    first_received = spawned[0] if spawned else {}
    if spawned and ms(host_bullet) is not None and ms(host_bullet) < ms(first_received):
        issues.append("first real bullet precedes its setup")
    if fire and queued and ms(fire) > ms(queued):
        issues.append("enqueue precedes real auto-fire")
    observed = [elapsed(ms(row), t0) for row in (guest_move, host_move, host_bullet)]
    confirmed = max(observed) if all(value is not None for value in observed) else None
    if confirmed is None or confirmed > 1000:
        issues.append("1 s readiness")
    applied = [row for row in packets(host, "position_applied") if host_move and row["slot"] == slot
               and abs(row["x"] - host_move["spawn_x"]) > 8 and ms(row) <= ms(host_move)]
    motion_stages = (packets(guest, "position_sent"), packets(host, "position_rpc"))
    if not any(all(any((row["slot"], row["x"], row["y"], row["status"]) == (slot, pos["x"], pos["y"], 0)
                       for row in stage) for stage in motion_stages) for pos in applied):
        issues.append("missing authoritative motion evidence")
    followups = [elapsed(ms(row), ms(host_bullet)) for row in spawned[1:3]]
    if len(followups) == 2 and followups[1] > 1300:
        issues.append("1.3 s followups")
    if any("SCRIPT ERROR" in log or any(line.startswith("ERROR:") and "resources still in use at exit" not in line
                                        for line in log.splitlines()) for log in (host, guest)):
        issues.append("engine or script error")
    first_rpc = next((row for row in incoming if row["batch"] == first_received.get("batch")), {})
    return {"case": name, "host_device": "4:3" if swap else "20:9", "failed": bool(issues), "issues": issues,
            "slot": slot, "round": round_id, "start_to_host_ready_ms": elapsed(host_ready, start),
            "start_to_guest_ready_ms": elapsed(guest_ready, start), "guest_input_bound_ms": elapsed(ms(bound), t0),
            "guest_move_ms": observed[0], "host_move_ms": observed[1], "first_authority_bullet_ms": observed[2],
            "local_auto_fire_ms": elapsed(ms(fire), t0), "local_queued_ms": elapsed(ms(queued), t0),
            "first_flush_ms": elapsed(ms(sent[0]), t0) if sent else None,
            "first_authority_rpc_ms": elapsed(ms(first_rpc), t0), "first_authority_setup_ms": elapsed(ms(first_received), t0),
            "guest_visual_bullet_ms": elapsed(ms(local_visual), t0), "authority_move_and_shot_ms": confirmed,
            "first_sent_batch": sent[0]["batch"] if sent else None, "first_authority_batch": first_received.get("batch"),
            "followups_after_first_ms": followups, "ordered_batches_sent": len(ordered),
            "reliable_batches_sent": len(reliable), "batches_at_authority": len(spawned)}


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
    if mode == "normal":
        return normal_timings(name, swap, *logs, codes)
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
    start_pressed = trace(host, "start_pressed")["wall_ms"]
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
            "start_to_authority_move_and_shot_ms": host_confirmed - start_pressed,
            "remix_selected_to_authority_move_and_shot_ms": (
                host_confirmed - trace(host, "remix_selected")["wall_ms"] if mode == "remix" else None),
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
    parser.add_argument("--normal-runs", type=int, default=1)
    parser.add_argument("--normal-only", action="store_true")
    parser.add_argument("--normal-recovery", action="store_true")
    parser.add_argument("--start-port", type=int, default=19910)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cases = [("normal" if args.normal_runs == 1 else f"normal-{i + 1}", "normal", i % 2 != 0, ())
             for i in range(args.normal_runs)]
    if args.normal_recovery:
        cases.append(("normal-recovery", "normal", True, ("recover",)))
    if not args.normal_only:
        cases += [(f"remix-{i + 1}", "remix", i % 2 != 0, ()) for i in range(args.remix_runs)]
        cases += [("rift", "rift", True, ()), ("remix-recovery", "remix", True, ("recover",)),
                  ("remix-timeout", "remix", False, ("entry-timeout",))]
    results = []
    failed = 0
    for index, (name, mode, swap, extra) in enumerate(cases):
        try:
            row = run_pair(output, name, args.start_port + index, mode, swap, *extra)
        except (AssertionError, StopIteration, subprocess.TimeoutExpired) as error:
            row = {"case": name, "failed": True, "detail": str(error)}
        failed += bool(row.get("failed"))
        print(json.dumps(row, ensure_ascii=False), flush=True)
        results.append(row)
    (output / "timings.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    return int(failed != 0)


if __name__ == "__main__":
    sys.exit(main())
