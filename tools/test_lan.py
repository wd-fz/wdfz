#!/usr/bin/env python3
"""Run isolated, real ENet host/client processes (no GPU or broadcast required)."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
from ci.lan_proxy import LanProxy
from ci.common import ENGINE

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules", action="store_true", help="run rule, transaction, save and six-route fixtures")
    parser.add_argument("--players", type=int, choices=(2, 4), default=2)
    parser.add_argument("--faults", action="store_true")
    parser.add_argument("--ui", action="store_true")
    parser.add_argument("--soak", action="store_true")
    parser.add_argument("--slow-load", action="store_true", help="block the first client scene load for 12 seconds")
    parser.add_argument("--restore", action="store_true", help="restart the host and recover the authoritative save over ENet")
    parser.add_argument("--ending", action="store_true", help="two-process whitelist route with controlled travel fixtures")
    parser.add_argument("--renderer", choices=("forward_plus", "mobile"))
    parser.add_argument("--display-driver", choices=("x11", "wayland"), default="x11")
    parser.add_argument("--seconds", type=int, default=18)
    args = parser.parse_args()
    if args.ending: args.seconds = max(30, args.seconds)
    if args.restore: args.seconds = max(24, args.seconds)
    if args.rules:
        reports = ROOT / "build/reports/lan/rules"
        reports.mkdir(parents=True, exist_ok=True)
        for script, label in (("run_unit", "UNIT"), ("authority", "AUTHORITY")):
            result = subprocess.run([ENGINE, "--headless", "--path", str(ROOT), "--script", f"res://tests/network/{script}.gd"], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
            (reports / f"{script}.log").write_text(result.stdout)
            if result.returncode or "ERROR:" in result.stdout or not re.search(rf"LAN {label}: [1-9]\d* checks, 0 failures", result.stdout):
                raise RuntimeError(result.stdout[-9000:])
            print(result.stdout.strip())
        return
    reports = ROOT / "build/reports/lan" / (f"{args.players}-players" + ("-faults" if args.faults else "") + ("-soak" if args.soak else "") + ("-ending" if args.ending else "") + ("-slow-load" if args.slow_load else "") + ("-restore" if args.restore else "") + ("-ui-" + (args.renderer or "headless") if args.ui else ""))
    reports.mkdir(parents=True, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    children = []
    summaries = []
    proxies = []
    try:
        for index in range(args.players):
            role = "host" if index == 0 else f"guest-{index}"
            env = os.environ.copy()
            env["XDG_DATA_HOME"] = str(reports / role / "user")
            path = reports / f"{role}.log"
            output = path.open("w")
            join_port = port
            if index and args.faults:
                proxy = LanProxy(port, seed=714 + index)
                proxies.append(proxy)
                join_port = proxy.port
            rendering = ["--windowed", "--rendering-method", args.renderer, "--rendering-driver", "vulkan", "--display-driver", args.display_driver] if args.renderer else ["--headless"]
            command = [ENGINE, *rendering, "--path", str(ROOT), "--audio-driver", "Dummy", "--max-fps", "60", "--script", "res://tests/network/peer.gd", "--", f"--role={role}", f"--port={join_port}", f"--players={args.players}", f"--seconds={args.seconds}"]
            if args.ui: command.extend(["--ui", f"--screenshots={reports}"])
            if args.soak: command.append("--soak")
            if args.slow_load: command.append("--slow-load")
            if args.ending: command.append("--ending")
            if args.restore: command.append("--restore")
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
            children.append((process, output, path))
            if index == 0:
                time.sleep(0.7)
        deadline = time.monotonic() + args.seconds * 2 + (180 if args.ui else 45)
        for process, output, path in children:
            code = process.wait(timeout=max(1, deadline - time.monotonic()))
            output.flush()
            text = path.read_text()
            match = re.search(r"LAN RESULT: (\{[^\n]+\})", text)
            if code or not match or "SCRIPT ERROR:" in text or "ERROR:" in text:
                raise RuntimeError(f"{path.name}: exit={code}\n{text[-9000:]}")
            if args.renderer and f"RENDERER VERIFIED: vulkan / {args.renderer}" not in text:
                raise RuntimeError(f"{path.name}: no verified Vulkan device")
            if args.renderer and f"DISPLAY VERIFIED: {args.display_driver}" not in text:
                raise RuntimeError(f"{path.name}: unexpected display backend")
            summary = json.loads(match[1])
            if summary["failures"]:
                raise RuntimeError(f"{path.name}: {summary}")
            summaries.append(summary)
        (reports / "summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
        (reports / "impairment.json").write_text(json.dumps([{"forwarded": p.forwarded, "dropped": p.dropped, "duplicated": p.duplicated} for p in proxies], indent=2) + "\n")
        print(f"LAN ENet: {args.players} independent processes, {sum(s['checks'] for s in summaries)} checks passed")
    finally:
        for process, output, _ in children:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            output.close()
        for proxy in proxies:
            proxy.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        sys.exit(str(error))
