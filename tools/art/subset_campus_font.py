"""Build the in-game Chinese font from Noto Sans CJK SC 2.004 (fontTools + Brotli).

Usage: python tools/art/subset_campus_font.py NotoSansCJKsc-Regular.otf
The upstream .ttc is also supported. The subset retains the upstream license
and the common GB2312 repertoire in addition to the text shipped by the game.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[2]


def repertoire():
    chars = set(chr(n) for n in range(32, 127))
    for lead in range(0xA1, 0xF8):
        for trail in range(0xA1, 0xFF):
            chars.update(bytes([lead, trail]).decode("gb2312", errors="ignore"))
    for directory in ("game", "content", "assets"):
        for path in (ROOT / directory).rglob("*"):
            if path.suffix in (".gd", ".tscn", ".tres", ".json"):
                text = path.read_text(encoding="utf-8")
                if path.suffix == ".json":
                    text = json.dumps(json.loads(text), ensure_ascii=False)
                chars.update(text)
    return {ord(c) for c in chars}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    source = parser.parse_args().source
    kwargs = {"fontNumber": 2} if source.suffix.lower() == ".ttc" else {}
    font = TTFont(source, recalcTimestamp=False, **kwargs)
    if font["name"].getDebugName(1) != "Noto Sans CJK SC":
        parser.error("the source must be Noto Sans CJK SC Regular")
    options = subset.Options()
    options.name_IDs += [0, 13, 14]
    options.layout_features = ["kern", "liga", "vert", "vrt2"]
    wanted = repertoire()
    han = {n for n in wanted if 0x3400 <= n <= 0x9FFF or 0x20000 <= n <= 0x323AF}
    missing = han.difference(font.getBestCmap())
    if missing:
        parser.error("the source lacks these Han characters: " + "".join(map(chr, sorted(missing))))
    builder = subset.Subsetter(options=options)
    builder.populate(unicodes=wanted)
    builder.subset(font)
    font.flavor = "woff2"
    output = ROOT / "content/fonts/campus-sc.res"
    # The project font is loaded before the editor imports anything on a fresh clone.
    # Package the compressed WOFF2 as a native FontFile with no importer dependency.
    with tempfile.TemporaryDirectory() as temp:
        woff = Path(temp) / "subset.woff2"
        font.save(woff)
        subprocess.run(["godot", "--headless", "--path", temp, "--script",
                        str(ROOT / "tools/art/package_font.gd"), "--", str(woff), str(output)], check=True)
    print(f"{len(font.getBestCmap())} code points, {output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
