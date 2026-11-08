"""Shared command runner with durable logs and Godot printed-error handling."""
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
ENGINE = os.environ.get("GODOT_BIN", "godot")


def run(label, command, reports, timeout=600, cwd=ROOT):
    reports.mkdir(parents=True, exist_ok=True)
    log = reports / f"{label}.log"
    print(f"[{label}] running (log: {log.relative_to(ROOT) if log.is_relative_to(ROOT) else log})", flush=True)
    deadline = time.monotonic() + timeout
    with log.open("w", encoding="utf-8") as output:
        process = subprocess.Popen(command, cwd=cwd, text=True, stdout=output, stderr=subprocess.STDOUT)
        try:
            # Some GDScript parse errors leave a SceneTree running forever. Fail immediately.
            with log.open(encoding="utf-8", errors="replace") as reader:
                tail = ""
                while process.poll() is None:
                    chunk = reader.read()
                    tail = (tail + chunk)[-16000:]
                    for line in chunk.splitlines():
                        if line.startswith("CASE:"):
                            print(line, flush=True)
                    if re.search(r"(?:SCRIPT ERROR:|ERROR:)", tail):
                        raise RuntimeError(f"{label} printed an engine error; see {log}")
                    if time.monotonic() > deadline:
                        raise RuntimeError(f"{label} exceeded {timeout}s; see {log}")
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            print(log.read_text(errors="replace")[-16000:])
            raise
    text = log.read_text(encoding="utf-8", errors="replace")
    if process.returncode or re.search(r"(?:SCRIPT ERROR:|ERROR:)", text):
        print(text[-16000:])
        raise RuntimeError(f"{label} failed (exit {process.returncode}); see {log}")
    for line in text.splitlines():
        if "FRAMEWORK TESTS:" in line or "EXPORT SMOKE:" in line:
            print(line, flush=True)
    print(f"[{label}] passed", flush=True)
    return text


def check_version(reports):
    expected = (ROOT / ".godot-version").read_text().strip()
    version = run("version", [ENGINE, "--version"], reports, timeout=30).strip()
    if not version.startswith(expected + ".stable."):
        raise RuntimeError(f"Use Godot {expected} stable; found {version}")
    return version
