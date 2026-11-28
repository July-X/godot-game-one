"""Run the ordinary enemy tests through title/lobby, including a delayed ENet link."""

import argparse
from contextlib import contextmanager
import heapq
import itertools
import os
from pathlib import Path
import select
import shutil
import socket
import subprocess
import tempfile
import threading
import time

GODOT = os.environ.get("GODOT", "godot")


@contextmanager
def delayed_link(seconds):
    if seconds == 0:
        yield 7777
        return
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as front, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as back:
        front.bind(("127.0.0.1", 0))
        back.bind(("127.0.0.1", 0))
        stop = threading.Event()

        def forward():
            peer = None
            queue = []
            order = itertools.count()
            while not stop.is_set():
                now = time.monotonic()
                while queue and queue[0][0] <= now:
                    _, _, out, address, packet = heapq.heappop(queue)
                    out.sendto(packet, address)
                interval = max(0, min(.02, queue[0][0] - now)) if queue else .02
                ready, _, _ = select.select((front, back), (), (), interval)
                for inbound in ready:
                    packet, address = inbound.recvfrom(65536)
                    if inbound is front:
                        peer = address
                        out, target = back, ("127.0.0.1", 7777)
                    elif peer is not None:
                        out, target = front, peer
                    else:
                        continue
                    heapq.heappush(queue, (time.monotonic() + seconds, next(order), out, target, packet))

        relay = threading.Thread(target=forward, daemon=True)
        relay.start()
        try:
            yield front.getsockname()[1]
        finally:
            stop.set()
            relay.join()


def run_case(output, name, *, solo=False, delayed=0, swap=False, headless=False, capture=True,
             render_peer="both", stabilize_render=False):
    folder = output / name
    folder.mkdir()
    roles = ("solo",) if solo else ("host", "guest")
    jobs = []
    with delayed_link(delayed) as port:
        try:
            for role in roles:
                wide = (role != "guest") != swap
                # Two non-overlapping Mac windows keep both render surfaces active.
                # The probe independently sets the internal canvas to 1600×720 / 960×720.
                resolution = ("1600x720" if wide else "960x720") if solo else ("680x306" if wide else "480x360")
                rendered = not headless and (solo or render_peer in (role, "both"))
                display = ["--windowed", "--resolution", resolution, "--position",
                           "30,45" if role != "guest" else "755,45"] if rendered else ["--headless"]
                with (folder / f"{role}.log").open("w", encoding="utf-8") as log:
                    jobs.append(subprocess.Popen(
                        [GODOT, *display, "--audio-driver", "Dummy", "--path", ".", "res://tests/ordinary_enemy_probe.tscn",
                         "--", role, str(folder), name, str(port), "wide" if wide else "tablet",
                         *([] if capture else ["no-capture"]), *(["stabilize-render"] if stabilize_render else [])],
                        stdout=log, stderr=subprocess.STDOUT))
                if role == "host":
                    time.sleep(.3)
            codes = [job.wait(timeout=75) for job in jobs]
        except subprocess.TimeoutExpired:
            codes = []
        finally:
            for job in jobs:
                if job.poll() is None:
                    job.terminate()
                    job.wait(timeout=10)
    logs = [(folder / f"{role}.log").read_text() for role in roles]
    valid = codes == [0] * len(roles) and all(
        "[ENEMY] SUMMARY" in log and not any("SCRIPT ERROR" in line or (
            line.startswith("ERROR:") and "resources still in use at exit" not in line) for line in log.splitlines())
        for log in logs)
    for role, log in zip(roles, logs):
        for line in log.splitlines():
            if line.startswith(("[ENEMY] SUMMARY", "[ENEMY] TIMEOUT")):
                print(name, role, line)
    print(name, "pass" if valid else "failed", folder, flush=True)
    return valid


def run_mixed_versions(output, baseline_ref):
    with tempfile.TemporaryDirectory(prefix="enemy-protocol-9-") as folder:
        baseline = Path(folder)
        subprocess.run(["git", "archive", "-o", str(baseline / "project.tar"), baseline_ref], check=True)
        subprocess.run(["tar", "xf", str(baseline / "project.tar"), "-C", folder], check=True)
        with (output / "protocol-9-import.log").open("w") as log:
            subprocess.run([GODOT, "--headless", "--path", folder, "--editor", "--import"],
                           stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
        return verify_mixed_versions(output, baseline)


def verify_mixed_versions(output, baseline):
    shutil.copy2("tests/lobby_start_probe.gd", baseline / "tests/lobby_start_probe.gd")
    outcomes = []
    folder = output / "versions"
    folder.mkdir()
    for old_host in (True, False):
        jobs, logs = [], []
        try:
            for host in (True, False):
                old = host == old_host
                role = "host" if host else "client"
                path = folder / f"{'9' if old_host else '10'}-host-{role}.log"
                logs.append(path)
                project = str(baseline) if old else "."
                with path.open("w", encoding="utf-8") as log:
                    jobs.append(subprocess.Popen(
                        [GODOT, "--headless", "--path", project, "res://tests/lobby_start_probe.tscn",
                         "--", role, "7777", "expect-mismatch", "discovery-wire"], stdout=log, stderr=subprocess.STDOUT))
                if host:
                    time.sleep(.4)
            codes = [job.wait(timeout=25) for job in jobs]
        except subprocess.TimeoutExpired:
            codes = []
        finally:
            for job in jobs:
                if job.poll() is None:
                    job.terminate()
                    job.wait(timeout=10)
        texts = [path.read_text() for path in logs]
        valid = codes == [0, 0] and all(
            "failed=0" in log and any(line.startswith("[LOBBY] VERSION_HINT ") and "两台设备更新" in line
                                      for line in log.splitlines())
            and not any(line.startswith(("ERROR:", "SCRIPT ERROR")) for line in log.splitlines())
            for log in texts)
        print("9 host" if old_host else "10 host", "pass" if valid else "failed", flush=True)
        outcomes.append(valid)
    return all(outcomes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--case", action="append",
                        choices=("solo", "solo-swap", "lan", "lan-swap", "delayed", "cancellation", "versions"))
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--no-capture", action="store_true")
    parser.add_argument("--stabilize-render", action="store_true",
                        help="Request a viewport frame if a desktop window stops swapping")
    parser.add_argument("--render-peer", choices=("host", "guest", "both"), default="guest",
                        help="Render the chosen peer in loopback runs; the guest render is needed for warning timing")
    parser.add_argument("--baseline-ref", default="188fb0255f07d815106e9c0253646529b841f4c1",
                        help="Protocol 9 commit for the mixed-version test")
    args = parser.parse_args()
    cases = args.case or ("solo", "lan", "lan-swap", "delayed", "cancellation")
    if (args.headless or args.render_peer == "host") and "cancellation" in cases:
        parser.error("cancellation tests withholding a rendered warning, so it requires a window")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for case in cases:
        if case == "versions":
            results.append(run_mixed_versions(output, args.baseline_ref))
        else:
            results.append(run_case(output, case, solo=case.startswith("solo"), delayed=.10 if case == "delayed" else 0,
                                    swap=case.endswith("swap"), headless=args.headless, capture=not args.no_capture,
                                    render_peer=args.render_peer, stabilize_render=args.stabilize_render))
    return int(not all(results))


if __name__ == "__main__":
    raise SystemExit(main())
