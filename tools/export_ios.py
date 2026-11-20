#!/usr/bin/env python3
"""Build and verify a re-signable, unsigned ARM64 iPhoneOS release on macOS."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from ci import ios_bundle, package_budget
from ci.common import ENGINE, ROOT, check_version, file_digest, run
from export_android import RELEASE_VERSION, RELEASE_VERSION_CODE


def main():
    if sys.platform != "darwin":
        sys.exit("iOS export needs macOS, Xcode and the pinned Godot iOS template")
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT):
        sys.exit("An unsigned release requires a clean source tree")
    packages = ROOT / "build/packages"
    packages.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    reports = ROOT / "build/reports/ios"
    engine = check_version(reports)
    xcode = run("xcode", ["xcodebuild", "-version"], reports).strip()
    # The headless macOS editor otherwise previews system font collections that FreeType
    # cannot open on the hosted runner. This flag only applies to these tooling processes.
    editor = [ENGINE, "--headless", "--text-driver", "Dummy", "--path", str(ROOT)]
    run("import", [*editor, "--editor", "--import"], reports, timeout=900)
    name = f"wdfz-{RELEASE_VERSION}-ios-arm64-unsigned"
    ipa = packages / (name + ".ipa")
    with tempfile.TemporaryDirectory(prefix="wdfz-iphoneos-") as temp:
        directory = Path(temp)
        project = directory / "wdfz.xcodeproj"
        package_budget.clear_report(ROOT, project)
        run("export", [*editor, "--export-release", "iOS Unsigned", str(project)], reports, timeout=900)
        optimization = package_budget.read_report(ROOT, project)
        run("build", ["xcodebuild", "-project", str(project), "-scheme", "wdfz", "-configuration", "Release",
                      "-sdk", "iphoneos", "-destination", "generic/platform=iOS", "-derivedDataPath", str(directory / "Derived"),
                      "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
                      "AD_HOC_CODE_SIGNING_ALLOWED=NO", "DEVELOPMENT_TEAM=", "build"], reports, timeout=1200)
        payload = directory / "Payload"
        payload.mkdir()
        app = payload / "wdfz.app"
        shutil.move(directory / "Derived/Build/Products/Release-iphoneos/wdfz.app", app)
        # Apple linkers can add an ad-hoc signature even when Xcode skips its signing phase.
        for path in app.rglob("*"):
            if path.is_file():
                with path.open("rb") as source:
                    magic = source.read(4)
                if magic in ios_bundle.MACH_MAGICS:
                    signature = subprocess.run(["codesign", "-d", str(path)], capture_output=True)
                    if signature.returncode == 0:
                        subprocess.run(["codesign", "--remove-signature", str(path)], check=True)
        archive = directory / ipa.name
        subprocess.run(["/usr/bin/zip", "-qry", str(archive), "Payload"], cwd=directory, check=True)
        ios_bundle.inspect_ipa(archive, RELEASE_VERSION, RELEASE_VERSION_CODE)
        shutil.move(archive, ipa)
    digest = file_digest(ipa)
    info = {"passed": True, "revision": revision, "working_tree_dirty": False, "engine": engine, "xcode": xcode,
            "version": RELEASE_VERSION, "build_number": RELEASE_VERSION_CODE, "package": ios_bundle.BUNDLE_ID,
            "platform": "ios", "sdk": "iphoneos", "architecture": "arm64", "minimum_os": ios_bundle.MINIMUM_OS,
            "release": True, "signed": False, "runtime_verified": False,
            "rendering_driver": "vulkan", "rendering_method": "mobile", "package_optimization": optimization,
            "file": ipa.name, "bytes": ipa.stat().st_size, "sha256": digest}
    (packages / (name + ".build.json")).write_text(json.dumps(info, indent=2) + "\n")
    ipa.with_suffix(".ipa.sha256").write_text(f"{digest}  {ipa.name}\n")
    print(f"Verified unsigned device IPA: {ipa.name}", flush=True)


if __name__ == "__main__":
    main()
