#!/usr/bin/env python3
"""Update/check the exported LAN content fingerprint (independent of build machine)."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'assets/lan_manifest.json'

def content():
    files = set()
    for folder in ('game/core', 'game/features', 'game/app', 'game/infrastructure/network', 'game/presentation/world', 'game/presentation/actors'):
        files.update((ROOT / folder).rglob('*.gd'))
    files.update((ROOT / 'assets/campus').rglob('*.json'))
    entries = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    return {'version': 1, 'digest': hashlib.sha256(json.dumps(entries, sort_keys=True).encode()).hexdigest(), 'files': entries}

if __name__ == '__main__':
    result = json.dumps(content(), ensure_ascii=False, indent=2) + '\n'
    if '--check' in sys.argv:
        if not TARGET.exists() or TARGET.read_text() != result:
            sys.exit('LAN rules changed: run python tools/lan_manifest.py and commit assets/lan_manifest.json')
    else:
        TARGET.write_text(result)
