#!/usr/bin/env python3
"""Check structure, import resources and run the real Godot regression suites."""
import argparse
import json
import re
import sys
from ci import quality
from ci.common import ENGINE, ROOT, check_version, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true", help="structure and tooling tests; no engine needed")
    parser.add_argument("--mode", choices=("headless", "windowed", "both"), default="headless")
    parser.add_argument("--windowed", action="store_true", help="alias for --mode both")
    parser.add_argument("--renderer", choices=("forward_plus", "mobile"), default="forward_plus",
                        help="Vulkan renderer for windowed tests; headless tests do not render")
    parser.add_argument("--display-driver", choices=("x11", "wayland"), default="x11")
    options = parser.parse_args()
    mode = "static" if options.static_only else "both" if options.windowed else options.mode
    reports = ROOT / "build/reports" / (mode if mode in ("static", "headless") else f"{mode}-{options.renderer}")
    reports.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    summary = {"mode": mode, "passed": False, "suites": {}}
    try:
        print(quality.check(ROOT), flush=True)
        run("tooling", [sys.executable, "-m", "unittest", "discover", "-s", "tests/tooling", "-v"], reports)
        if not options.static_only:
            summary["engine"] = check_version(reports)
            run("import", [ENGINE, "--headless", "--path", str(ROOT), "--editor", "--import"], reports, timeout=900)
            for display in (("headless", "windowed") if mode == "both" else (mode,)):
                args = ["--headless"] if display == "headless" else ["--windowed", "--rendering-method", options.renderer,
                                                                      "--rendering-driver", "vulkan", "--display-driver", options.display_driver]
                output = run(display, [ENGINE, *args, "--path", str(ROOT), "--audio-driver", "Dummy",
                                      "--fixed-fps", "60", "--script", "res://tests/run_tests.gd"], reports,
                             timeout=5400 if display == "windowed" else 900)
                result = re.search(r"FRAMEWORK TESTS: (\d+) checks, 0 failures", output)
                if not result or int(result[1]) == 0:
                    raise RuntimeError(f"{display}: test runner did not confirm a completed, nonempty suite")
                if display == "windowed" and f"RENDERER VERIFIED: vulkan / {options.renderer}" not in output:
                    raise RuntimeError(f"{display}: no real Vulkan rendering device was verified")
                summary["suites"][display] = int(result[1])
                if display == "windowed":
                    summary["rendering_driver"] = "vulkan"
                    summary["rendering_method"] = options.renderer
        summary["passed"] = True
    finally:
        (reports / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(str(error))
