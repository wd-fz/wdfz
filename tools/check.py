#!/usr/bin/env python3
"""Import and test with the actual Godot engine; fail on script errors too."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = os.environ.get("GODOT_BIN", "godot")


def run(*args, timeout=120):
    result = subprocess.run(args, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, end="", flush=True)
    # Godot may return zero on a script parse error. Never accept that as success.
    if result.returncode or re.search(r"(?:SCRIPT ERROR:|ERROR:)", result.stdout):
        raise SystemExit(result.returncode or 1)
    return result.stdout


def check_boundaries():
    forbidden = re.compile(
        r"\b(?:Input|FileAccess|DirAccess|RenderingServer|DisplayServer)\s*\."
        r"|\b(?:get_tree|get_node)\s*\(|^\s*extends\s+(?:Node\w*|Control)\b"
    )
    paths = list((ROOT / "core/domain").glob("*.gd"))
    paths += list((ROOT / "core/modules").glob("*.gd"))
    paths += list((ROOT / "core/session").glob("*.gd"))
    for path in (ROOT / "features").rglob("*.gd"):
        if re.search(r"^extends FeatureModule$", path.read_text(), re.M):
            paths.append(path)
    for path in paths:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("#", 1)[0]
            if forbidden.search(code):
                raise SystemExit(f"Rule layer depends on an adapter: {path.relative_to(ROOT)}:{number}")
    print(f"Layer boundary check: {len(paths)} rule scripts passed.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windowed", action="store_true", help="also verify real window input (requires a display)")
    options = parser.parse_args()
    expected = (ROOT / ".godot-version").read_text().strip()
    version = run(ENGINE, "--version").strip()
    if not version.startswith(expected + "."):
        raise SystemExit(f"Use Godot {expected}; found {version}")
    check_boundaries()
    run(ENGINE, "--headless", "--path", str(ROOT), "--editor", "--import")
    run(ENGINE, "--headless", "--path", str(ROOT), "--fixed-fps", "60",
        "--script", "res://tests/run_tests.gd")
    if options.windowed:
        run(ENGINE, "--path", str(ROOT), "--rendering-method", "gl_compatibility",
            "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--script", "res://tests/run_tests.gd")


if __name__ == "__main__":
    try:
        main()
    except subprocess.TimeoutExpired as error:
        if error.stdout:
            print(error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout)
        sys.exit(str(error))
    except OSError as error:
        sys.exit(str(error))
