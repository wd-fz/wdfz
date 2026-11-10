#!/usr/bin/env python3
"""Bind generated art cells to stable game IDs; PNGs are kept unchanged."""
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/ui/illustrations"
SHEETS = [
    ("items_01", "items", 4, 4, [
        "card", "phone", "chalk", "map", "key", "torch", "brolly", "coat",
        "pill", "notebook", "pen", "snack", "battery", "compass", "metronome", "goggles",
    ]),
    ("items_02", "items", 4, 4, [
        "hw", "coin", "usb", "watch", "memo", "roomkey", "coil", "lens",
        "vial", "atlas", "elixir", "seal", "leave", "paper", "medkit", "small_knife",
    ]),
    ("items_03", "items", 3, 3, [
        "top", "archivekey", "broadcastkey", "broadcastfuse", "notice_fake",
        "notice1", "notice2", "notice3", "notice4",
    ]),
    ("talents", "talents", 4, 2, ["tech", "code", "drive", "night", "watch", "immune", "ear", "random"]),
    ("phone_apps", "phone", 4, 2, ["home", "wireless", "location", "sync", "container", "camera", "plane", "battery"]),
]


def main():
    manifest = {}
    expansion = json.loads((ART / "expansion_sheets.json").read_text(encoding="utf-8"))
    for sheet, group, columns, rows, ids in SHEETS + expansion:
        entries = manifest.setdefault(group, {})
        png = ART / "atlases" / f"{sheet}.png"
        header = png.read_bytes()[:24]
        if header[:8] != b"\x89PNG\r\n\x1a\n" or len(ids) != columns * rows:
            raise ValueError(f"Invalid sheet: {sheet}")
        width, height = struct.unpack(">II", header[16:24])
        folder = ART / group
        folder.mkdir(exist_ok=True)
        for index, name in enumerate(ids):
            x = (index % columns) * width / columns
            y = (index // columns) * height / rows
            filename = name.replace(":", "_").replace(".", "_")
            resource = folder / f"{filename}.tres"
            if name in entries or "res://" + resource.relative_to(ROOT).as_posix() in entries.values():
                raise ValueError(f"Duplicate art ID or filename: {group}/{name}")
            texture_path = "res://" + png.relative_to(ROOT).as_posix()
            resource.write_text(
                '[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" path="{texture_path}" id="1"]\n\n'
                '[resource]\natlas = ExtResource("1")\n'
                f'region = Rect2({x:g}, {y:g}, {width / columns:g}, {height / rows:g})\n'
                'filter_clip = true\n', encoding="utf-8",
            )
            entries[name] = "res://" + resource.relative_to(ROOT).as_posix()
    known_items = set(json.loads((ROOT / "assets/campus/layout/campus.json").read_text())["items"])
    if known_items != set(manifest["items"]):
        raise ValueError("Art IDs must cover the complete item catalog")
    (ART / "catalog.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Art resources: " + ", ".join(f"{group}: {len(entries)}" for group, entries in manifest.items()))


if __name__ == "__main__":
    main()
