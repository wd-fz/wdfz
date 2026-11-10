#!/usr/bin/env python3
"""Compare actual Vulkan wall/GPU times without a fixed simulation frame rate."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--renderer", choices=("forward_plus", "mobile", "both"), default="both")
    parser.add_argument("--scene", action="append", choices=("teach1", "out", "admin5", "garage1"))
    parser.add_argument("--quality", type=int, choices=range(5), default=2)
    parser.add_argument("--samples", type=int, default=60)
    parser.add_argument("--compare", action="store_true", help="also measure the original submission/mipmap/portal path")
    parser.add_argument("--ablate", action="store_true", help="add individual post/shadow/light/preview ablations")
    parser.add_argument("--display-driver", choices=("x11", "wayland"), default="x11")
    parser.add_argument("--output", type=Path, default=ROOT / "build/reports/render-profile")
    options = parser.parse_args()
    if options.samples < 4:
        parser.error("at least 4 samples are required")
    options.output = options.output.resolve()
    options.output.mkdir(parents=True, exist_ok=True)
    renderers = ("forward_plus", "mobile") if options.renderer == "both" else (options.renderer,)
    rows = []
    for renderer in renderers:
        for scene in options.scene or ["teach1", "out", "admin5", "garage1"]:
            pair = {}
            for reference in ([True, False] if options.compare else [False]):
                name = f'{renderer}-{scene}-q{options.quality}-{"reference" if reference else "optimized"}'
                path = options.output / (name + ".json")
                command = [os.environ.get("GODOT_BIN", "godot"), "--path", str(ROOT), "--windowed",
                           "--audio-driver", "Dummy", "--display-driver", options.display_driver,
                           "--rendering-method", renderer, "--rendering-driver", "vulkan",
                           "--script", "res://tools/benchmarks/render_profile.gd", "--", str(path),
                           f"--scene={scene}", f"--quality={options.quality}", f"--samples={options.samples}"]
                if reference:
                    command.append("--reference")
                if not options.ablate:
                    command.append("--quick")
                print(f"Measuring {name}…", flush=True)
                # Sequential windows: focus changes must not pause one of two competing runs.
                run = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, timeout=900)
                (options.output / (name + ".log")).write_text(run.stdout)
                if run.returncode or "SCRIPT ERROR:" in run.stdout or "ERROR:" in run.stdout:
                    raise RuntimeError(f"{name} failed; inspect {name}.log")
                report = json.loads(path.read_text())
                if report["driver"] != "vulkan" or report["renderer"] != renderer:
                    raise RuntimeError("The benchmark did not use the requested Vulkan renderer")
                pair["reference" if reference else "optimized"] = report
            row = {"renderer": renderer, "scene": scene, "quality": options.quality,
                   "device": pair["optimized"]["device"], "samples": options.samples,
                   "optimized": pair["optimized"]["cases"]["baseline"]}
            if "reference" in pair:
                row["reference"] = pair["reference"]["cases"]["baseline"]
                row["reduction_percent"] = {
                    metric: round(100 * (1 - row["optimized"][metric]["mean"] / row["reference"][metric]["mean"]), 2)
                    for metric in ("wall_ms", "gpu_ms", "render_cpu_ms", "draw_calls", "primitives")
                    if row["reference"][metric]["mean"] > 0}
                row["median_reduction_percent"] = {
                    metric: round(100 * (1 - row["optimized"][metric]["median"] / row["reference"][metric]["median"]), 2)
                    for metric in ("wall_ms", "gpu_ms", "render_cpu_ms")
                    if row["reference"][metric]["median"] > 0}
            rows.append(row)
            (options.output / "summary.json").write_text(json.dumps(rows, indent=2) + "\n")
            print(json.dumps(row, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
