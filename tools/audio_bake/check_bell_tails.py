#!/usr/bin/env python3
"""Check encoded bell variants against original note fixtures (requires NumPy and ffmpeg)."""
import gzip
import json
from pathlib import Path
import subprocess

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050


def decode(name):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(ROOT / "assets/audio/sfx" / name),
        "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-",
    ])
    return np.frombuffer(raw, dtype="<f4")


def main():
    index = json.loads((ROOT / "assets/audio/index.json").read_text())
    data = json.loads(gzip.decompress((ROOT / "tests/fixtures/bell_tails-reference.json.gz").read_bytes()))
    original = index["sfx"]["event.bellEnd"]["files"][0]
    base = decode(original["file"]) * 10 ** (original["db"] / 20)
    reports = []
    for variant in index["bell_tails"]:
        sample = next(s for s in data["samples"] if s["tune"].get("tail") == variant["tail"]
                      and s["tune"].get("tailLength") == variant["tailLength"])
        note = sample["notes"][-1]
        take = variant["files"][0]
        decoded = decode(take["file"]) * 10 ** (take["db"] / 20)
        # Avoid the Vorbis overlap block around the changed final note.
        prefix = int((note["at"] - .12) * RATE)
        correlation = float(np.corrcoef(base[:prefix], decoded[:prefix])[0, 1])
        gain_db = float(20 * np.log10(np.sqrt(np.mean(decoded[:prefix] ** 2)) /
                                    np.sqrt(np.mean(base[:prefix] ** 2))))
        segment = decoded[int((note["at"] + .28) * RATE):int((note["at"] + 1.68) * RATE)]
        spectrum = np.abs(np.fft.rfft(segment * np.hanning(len(segment)), n=262144))
        hz = np.fft.rfftfreq(262144, 1 / RATE)
        expected = note["frequency"]
        region = (hz > expected * .95) & (hz < expected * 1.05)
        peak = float(hz[region][np.argmax(spectrum[region])])
        duration = len(decoded) / RATE
        # The original bell recipe detunes individual partials by up to 0.1%.
        if correlation <= .999 or abs(gain_db) >= .02 or abs(peak - expected) >= 1 or abs(duration - variant["len"]) >= .02:
            raise ValueError(f"Bell differs: {take['file']}: {correlation=}, {gain_db=}, {peak=}, {expected=}, {duration=}")
        reports.append({"file": take["file"], "prefix_correlation": correlation,
                        "prefix_gain_db": gain_db, "tail_hz": peak,
                        "original_tail_hz": expected, "duration": duration})
    if len(reports) != 4:
        raise ValueError("Expected all four original day/night tail variants")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
