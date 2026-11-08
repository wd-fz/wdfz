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
    options = parser.parse_args()
    mode = "static" if options.static_only else "both" if options.windowed else options.mode
    reports = ROOT / "build/reports" / mode
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
                args = ["--headless"] if display == "headless" else ["--windowed", "--rendering-method", "gl_compatibility"]
                output = run(display, [ENGINE, *args, "--path", str(ROOT), "--audio-driver", "Dummy",
                                      "--fixed-fps", "60", "--script", "res://tests/run_tests.gd"], reports,
                             timeout=3600 if display == "windowed" else 900)
                result = re.search(r"FRAMEWORK TESTS: (\d+) checks, 0 failures", output)
                if not result or int(result[1]) == 0:
                    raise RuntimeError(f"{display}: test runner did not confirm a completed, nonempty suite")
                summary["suites"][display] = int(result[1])
        summary["passed"] = True
    finally:
        (reports / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        sys.exit(str(error))
