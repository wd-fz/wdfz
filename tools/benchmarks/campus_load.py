#!/usr/bin/env python3
"""Measure Linux campus entry and exit with new/continue in separate Godot processes.

Run after importing the checkout. Use the same renderer, machine, resolution and
quality for both revisions. Each sample starts with a fresh user profile; the
continue case uses the save and driver cache created by its corresponding new game.
Headless mode measures simulation and loading only.
"""
import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).with_name("campus_load.gd")
PREFIX = "CAMPUS LOAD RESULT "


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--project", type=Path, help="imported checkout; defaults to this repository")
    source.add_argument("--main-pack", type=Path, help="exported .pck to benchmark with the matching Godot editor")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--display", choices=("x11", "wayland", "headless"), default="x11")
    parser.add_argument("--renderer", choices=("forward_plus", "mobile"), default="mobile")
    parser.add_argument("--quality", type=int, choices=range(5), default=2)
    parser.add_argument("--resolution", default="960x540")
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--output", type=Path, default=ROOT / "build/reports/campus-load")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        parser.error("this runner uses isolated Linux XDG profiles")
    if args.samples < 1 or args.timeout < 1:
        parser.error("samples and timeout must be positive")
    if not re.fullmatch(r"[1-9][0-9]*x[1-9][0-9]*", args.resolution):
        parser.error("resolution must be WIDTHxHEIGHT")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    command = [args.godot, "--audio-driver", "Dummy"]
    if args.main_pack:
        if not args.main_pack.is_file():
            parser.error(f"pack does not exist: {args.main_pack}")
        command.extend(["--main-pack", str(args.main_pack.resolve())])
    else:
        command.extend(["--path", str((args.project or ROOT).resolve())])
    if args.display == "headless":
        command.append("--headless")
    else:
        command.extend(["--display-driver", args.display, "--rendering-driver", "vulkan",
                        "--rendering-method", args.renderer, "--windowed", "--resolution", args.resolution])
    command.extend(["--script", str(SCRIPT), "--", f"--quality={args.quality}"])
    rows = []
    for sample in range(1, args.samples + 1):
        with tempfile.TemporaryDirectory(prefix="wdfz-campus-load-") as profile:
            env = os.environ.copy()
            for key in ("DATA", "CONFIG", "CACHE"):
                env[f"XDG_{key}_HOME"] = str(Path(profile) / key.lower())
            for scenario in ("new", "continue"):
                log = output / f"{sample}-{scenario}.log"
                print(f"Running {sample}/{args.samples} {scenario} ({log})", flush=True)
                with log.open("w") as stream:
                    try:
                        finished = subprocess.run([*command, f"--case={scenario}"], env=env, cwd=profile,
                                                  stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout)
                    except subprocess.TimeoutExpired:
                        sys.exit(f"{scenario} exceeded {args.timeout}s; see {log}")
                lines = log.read_text().splitlines()
                results = [line[len(PREFIX):] for line in lines if line.startswith(PREFIX)]
                if finished.returncode or len(results) != 1 or any(
                    "SCRIPT ERROR:" in line or "ERROR:" in line for line in lines
                ):
                    sys.exit(f"{scenario} failed; see {log}")
                row = json.loads(results[0])
                if args.display != "headless" and (row["renderer"], row["driver"]) != (args.renderer, "vulkan"):
                    sys.exit(f"requested Vulkan backend unavailable; see {log}")
                if args.display != "headless" and row["resolution"] != [int(n) for n in args.resolution.split("x")]:
                    sys.exit(f"actual window size differs from --resolution; see {log}")
                rows.append(dict(sample=sample, **row))
                print(f"{sample} {scenario}: playable {row['playable_ms']:.0f} ms, "
                      f"doorway {row['doorway_ms']:.0f} ms", flush=True)
    medians = {scenario: {key: statistics.median(row[key] for row in rows if row["scenario"] == scenario)
                          for key in ("loading_complete_ms", "playable_ms", "entry_worst_frame_ms", "doorway_ms")}
               for scenario in ("new", "continue")}
    (output / "summary.json").write_text(json.dumps({"samples": rows, "median_ms": medians}, indent=2) + "\n")


if __name__ == "__main__":
    main()
