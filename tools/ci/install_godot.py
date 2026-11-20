#!/usr/bin/env python3
"""Install the pinned official editor and selected export templates."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ("linux_release.x86_64", "windows_release_x86_64.exe", "version.txt")


def download(url, path):
    temporary = path.with_suffix(path.suffix + ".part")
    with urllib.request.urlopen(url, timeout=120) as source, temporary.open("wb") as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
    temporary.replace(path)


def digest(path):
    value = hashlib.sha512()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def verified_archive(release, name, cache):
    sums = urllib.request.urlopen(release + "/SHA512-SUMS.txt", timeout=60).read().decode()
    matches = [line.split()[0] for line in sums.splitlines() if len(line.split()) == 2 and line.split()[1].lstrip("*") == name]
    if len(matches) != 1:
        raise RuntimeError(f"Official checksum missing or ambiguous: {name}")
    archive = cache / name
    print(f"Downloading and verifying {name}", flush=True)
    download(release + "/" + name, archive)
    if digest(archive) != matches[0]:
        archive.unlink()
        raise RuntimeError(f"SHA512 mismatch: {name}")
    return archive


def extract_member(archive, member, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle, bundle.open(member) as source, target.open("wb") as output:
        shutil.copyfileobj(source, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/wdfz-godot")
    parser.add_argument("--templates", action="store_true")
    parser.add_argument("--ios", action="store_true", help="install the official iOS export template on macOS")
    parser.add_argument("--android-debug", action="store_true", help="install the official Android Gradle template with prebuilt engine libraries")
    parser.add_argument("--android-release", action="store_true", help="install the official Android Gradle template with prebuilt engine libraries")
    args = parser.parse_args()
    version = (ROOT / ".godot-version").read_text().strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("Invalid pinned engine version")
    cache = args.cache.expanduser().resolve() / version
    cache.mkdir(parents=True, exist_ok=True)
    release = f"https://github.com/godotengine/godot-builds/releases/download/{version}-stable"
    engine = cache / "bin/godot"
    mac = sys.platform == "darwin"
    if args.ios and not mac:
        parser.error("Building an iPhoneOS application requires macOS and Xcode")
    if not engine.exists():
        platform = "macos.universal" if mac else "linux.x86_64"
        name = f"Godot_v{version}-stable_{platform}"
        archive = verified_archive(release, name + ".zip", cache)
        if mac:
            engine.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["ditto", "-x", "-k", archive, engine.parent], check=True)
            engine.symlink_to("Godot.app/Contents/MacOS/Godot")
        else:
            extract_member(archive, name, engine)
            engine.chmod(0o755)
        archive.unlink()
    selected = list(TEMPLATES) if args.templates else []
    if args.ios:
        selected += [name for name in ("ios.zip", "version.txt") if name not in selected]
    if args.android_debug or args.android_release:
        selected += [name for name in ("android_source.zip", "version.txt") if name not in selected]
    if selected:
        template_cache = cache / "templates"
        if not all((template_cache / name).is_file() for name in selected):
            archive = verified_archive(release, f"Godot_v{version}-stable_export_templates.tpz", cache)
            for name in selected:
                extract_member(archive, "templates/" + name, template_cache / name)
            archive.unlink()
        data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        godot_data = Path.home() / "Library/Application Support/Godot" if mac else data_home / "godot"
        destination = godot_data / "export_templates" / f"{version}.stable"
        destination.mkdir(parents=True, exist_ok=True)
        for name in selected:
            shutil.copy2(template_cache / name, destination / name)
        print(f"Export templates ({', '.join(selected)}): {destination}")
    if os.environ.get("GITHUB_PATH"):
        with open(os.environ["GITHUB_PATH"], "a") as output:
            output.write(str(engine.parent) + "\n")
    print(f"Godot executable: {engine}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
