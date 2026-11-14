#!/usr/bin/env python3
"""Publish Android, Windows and Linux together after verifying every release asset."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile
from export_android import RELEASE_PACKAGE, RELEASE_VERSION, RELEASE_VERSION_CODE
import terracotta


def validate_android(folder, revision):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Expected a full source commit")
    name = f"wdfz-{RELEASE_VERSION}-android-arm64"
    apk = folder / f"{name}.apk"
    checksum = folder / f"{name}.apk.sha256"
    metadata = folder / f"{name}.build.json"
    info = json.loads(metadata.read_text())
    expected = {"passed": True, "debug": False, "working_tree_dirty": False, "revision": revision,
                "package": RELEASE_PACKAGE, "version": RELEASE_VERSION, "version_code": RELEASE_VERSION_CODE,
                "abi": "arm64-v8a", "min_sdk": 24, "target_sdk": 36, "page_alignment": 16384,
                "launch_orientation": "userLandscape", "file": apk.name,
                "rendering_driver": "vulkan", "rendering_method": "mobile", "vulkan_required": True,
                "fullscreen_forced": True, "build_system": "gradle", "terracotta": terracotta.VERSION}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("Release bundle does not match the verified release build and source")
    if not re.fullmatch(r"[0-9a-f]{64}", info.get("signing_certificate_sha256", "")):
        raise ValueError("Release signing certificate fingerprint is missing")
    digest = file_digest(apk)
    if (digest != info.get("sha256") or apk.stat().st_size != info.get("bytes")
            or checksum.read_text().strip() != f"{digest}  {apk.name}"):
        raise ValueError("APK, metadata and checksum do not agree")
    return [apk, checksum, metadata]



def validate_desktop(folder, revision, platform):
    name = f"wdfz-{RELEASE_VERSION}-{platform}-x86_64"
    archive = folder / (name + ".zip")
    checksum = folder / (name + ".zip.sha256")
    metadata = folder / (name + ".build.json")
    info = json.loads(metadata.read_text())
    expected = {"passed": True, "release": True, "working_tree_dirty": False, "revision": revision,
                "version": RELEASE_VERSION, "platform": platform, "terracotta": terracotta.VERSION, "rendering_driver": "vulkan",
                "rendering_method": "forward_plus", "window_default": "windowed", "file": archive.name,
                "runtime_verified": platform == "linux", "rendering_verified": platform == "linux",
                "display_drivers_verified": ["x11", "wayland"] if platform == "linux" else []}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError(f"{platform} bundle does not match verified release source and display policy")
    digest = file_digest(archive)
    if (digest != info.get("sha256") or archive.stat().st_size != info.get("bytes")
            or checksum.read_text().strip() != f"{digest}  {archive.name}"):
        raise ValueError(f"{platform} package, metadata and checksum do not agree")
    with zipfile.ZipFile(archive) as bundle:
        prefix = f"wdfz-{platform}/"
        binary = "wdfz.x86_64" if platform == "linux" else "wdfz.exe"
        required = {prefix + item for item in (binary, "wdfz.pck", "BUILD.json", "LICENSE", "README.txt")}
        component = "terracotta" if platform == "linux" else "terracotta.exe"
        required.update(prefix + "terracotta/" + item for item in (component, "LICENSE", "NOTICE.md", "dependency.json"))
        if platform == "windows": required.add(prefix + "terracotta/VCRUNTIME140.DLL")
        if set(bundle.namelist()) != required or bundle.testzip() is not None:
            raise ValueError(f"{platform} archive content is incomplete or corrupt")
        dependency = json.loads(bundle.read(prefix + "terracotta/dependency.json"))
        if dependency != {"version": terracotta.VERSION, "source": terracotta.SOURCE,
                          "archive_sha256": terracotta.ASSETS[platform][1]}:
            raise ValueError(f"{platform} Terracotta dependency does not match the pinned official release")
        inside = json.loads(bundle.read(prefix + "BUILD.json"))
        if not inside or any(info.get(key) != value for key, value in inside.items()):
            raise ValueError(f"{platform} archive provenance differs from its sidecar")
        for key in ("revision", "version", "platform", "release", "working_tree_dirty", "window_default", "display_drivers_verified", "terracotta"):
            if inside.get(key) != expected[key]: raise ValueError(f"{platform} archive missing {key}")
        if platform == "linux" and not (bundle.getinfo(prefix + binary).external_attr >> 16) & 0o111:
            raise ValueError("Linux executable permission missing from ZIP")
    return [archive, checksum, metadata]


def validate_bundle(folder, revision):
    files = validate_android(folder, revision)
    for platform in ("windows", "linux"):
        files.extend(validate_desktop(folder, revision, platform))
    if set(path.name for path in folder.iterdir()) != set(path.name for path in files):
        raise ValueError("Release folder contains unexpected assets")
    return files


def file_digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--notes", type=Path, required=True)
    parser.add_argument("--draft-only", action="store_true",
                        help="upload and verify the assets on a draft release, then stop without publishing")
    args = parser.parse_args()
    if args.tag != "v" + RELEASE_VERSION:
        raise ValueError("Tag must match the release version")
    revision = os.environ["GITHUB_SHA"]
    files = validate_bundle(args.assets, revision)
    repo = os.environ["GITHUB_REPOSITORY"]

    def api(path, optional=False):
        result = subprocess.run(["gh", "api", f"repos/{repo}/{path}"], capture_output=True, text=True)
        if optional and result.returncode and "(HTTP 404)" in result.stderr:
            return None
        if result.returncode:
            raise RuntimeError(f"GitHub could not verify {path}")
        return json.loads(result.stdout)

    # A pre-existing tag must also point at the verified source, even for a draft.
    ref = api(f"git/ref/tags/{args.tag}", optional=True)
    if ref:
        obj = ref["object"]
        for _ in range(5):
            if obj["type"] != "tag": break
            obj = api(f"git/tags/{obj['sha']}")["object"]
        if obj["type"] != "commit" or obj["sha"] != revision:
            raise ValueError("Existing release tag points at different source")
    def release_by_tag():
        # REST /releases/tags does not expose an unpublished tag. gh resolves
        # drafts through GraphQL; subsequent verification uses its numeric ID.
        result = subprocess.run(["gh", "release", "view", args.tag, "--repo", repo, "--json", "apiUrl"], capture_output=True, text=True)
        if result.returncode:
            if "release not found" in result.stderr.lower(): return None
            raise RuntimeError("GitHub could not resolve the release destination")
        release_id = json.loads(result.stdout)["apiUrl"].rsplit("/",1)[-1]
        if not release_id.isdigit(): raise ValueError("Invalid release identifier")
        return api(f"releases/{release_id}")

    release = release_by_tag()
    if release is None:
        subprocess.run(["gh", "release", "create", args.tag, "--repo", repo, "--draft", "--target", revision,
                        "--title", f"{args.tag} · Android / Windows / Linux", "--notes-file", str(args.notes)], check=True)
        release = release_by_tag()
    if not release["draft"] or release["target_commitish"] != revision:
        raise ValueError("Refusing to modify a public release or a draft for different source")
    existing = {asset["name"]: asset for asset in release["assets"]}
    if set(existing) - {file.name for file in files}:
        raise ValueError("Draft contains assets outside this verified release")
    pending = []
    for file in files:
        remote = existing.get(file.name)
        if remote is None:
            pending.append(str(file))
        elif (remote.get("state") != "uploaded" or remote.get("size") != file.stat().st_size
              or remote.get("digest") != "sha256:" + file_digest(file)):
            raise ValueError(f"Refusing to replace a different draft asset: {file.name}")
    if pending:
        subprocess.run(["gh", "release", "upload", args.tag, "--repo", repo, *pending], check=True)
    release = api(f"releases/{release['id']}")
    assets = {asset["name"]: asset for asset in release["assets"]}
    for file in files:
        remote = assets.get(file.name, {})
        if (remote.get("state") != "uploaded" or remote.get("size") != file.stat().st_size
                or remote.get("digest") != "sha256:" + file_digest(file)):
            raise ValueError(f"Uploaded asset did not verify: {file.name}")
    if not release["draft"]:
        raise ValueError("Release unexpectedly changed during upload")
    if args.draft_only:
        print("Draft ready (not published) " + release["html_url"])
        return
    subprocess.run(["gh", "release", "edit", args.tag, "--repo", repo, "--draft=false", "--latest"], check=True)
    release = api(f"releases/{release['id']}")
    if release["draft"] or release["prerelease"]:
        raise RuntimeError("Release was not publicly published")
    print("Published " + release["html_url"])


if __name__ == "__main__":
    main()
