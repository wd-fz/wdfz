import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from publish_release import validate_android as validate_bundle
from publish_release import validate_bundle as validate_all
from publish_release import validate_ios
from export_android import RELEASE_VERSION, RELEASE_VERSION_CODE
import terracotta


class PublicReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.apk = self.folder / f"wdfz-{RELEASE_VERSION}-android-arm64.apk"
        self.apk.write_bytes(b"synthetic checksum fixture")
        self.sha = "1" * 40
        digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.info = {"passed": True, "debug": False, "working_tree_dirty": False, "revision": self.sha,
                     "package": "org.wdfz.godot", "version": RELEASE_VERSION, "version_code": RELEASE_VERSION_CODE,
                     "abi": "arm64-v8a", "min_sdk": 24, "target_sdk": 36, "page_alignment": 16384,
                     "launch_orientation": "userLandscape", "file": self.apk.name,
                     "rendering_driver": "vulkan", "rendering_method": "mobile", "vulkan_required": True,
                     "fullscreen_forced": True, "build_system": "gradle", "terracotta": terracotta.VERSION,
                     "signing_certificate_sha256": "2"*64, "sha256": digest, "bytes": self.apk.stat().st_size}
        self.meta = self.apk.with_suffix(".build.json")
        self.meta.write_text(json.dumps(self.info))
        self.apk.with_suffix(".apk.sha256").write_text(f"{digest}  {self.apk.name}\n")
        self.add_ios()

    def add_ios(self, *, platform=2, cpu=0x0100000C, signature=False, extra=None, pack=b"GDPCfixture", metal=True):
        name = f"wdfz-{RELEASE_VERSION}-ios-arm64-unsigned"
        ipa = self.folder / (name + ".ipa")
        orientations = ["UIInterfaceOrientationLandscapeRight", "UIInterfaceOrientationLandscapeLeft"]
        plist = {"CFBundlePackageType": "APPL", "CFBundleIdentifier": "org.wdfz.godot",
                 "CFBundleShortVersionString": RELEASE_VERSION, "CFBundleVersion": str(RELEASE_VERSION_CODE),
                 "CFBundleExecutable": "wdfz", "CFBundleSupportedPlatforms": ["iPhoneOS"], "MinimumOSVersion": "14.0",
                 "UIRequiresFullScreen": True, "UISupportedInterfaceOrientations": orientations,
                 "UISupportedInterfaceOrientations~ipad": orientations, "UIDeviceFamily": [1, 2],
                 "NSLocalNetworkUsageDescription": "Connect to local players"}
        commands = struct.pack("<6I", 0x32, 24, platform, 0xE0000, 0x120000, 0)
        count = 1
        if metal:
            lib = b"/System/Library/Frameworks/Metal.framework/Metal" + bytes(1)
            lib = lib.ljust((len(lib) + 7) // 8 * 8, bytes(1))
            commands += struct.pack("<6I", 0xC, 24 + len(lib), 24, 0, 0, 0) + lib
            count += 1
        if signature:
            count += 1
            commands += struct.pack("<4I", 0x1D, 16, 0, 0)
        binary = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, count, len(commands), 0, 0) + commands
        root = "Payload/wdfz.app/"
        with zipfile.ZipFile(ipa, "w") as bundle:
            executable = zipfile.ZipInfo(root + "wdfz")
            executable.external_attr = 0o100755 << 16
            bundle.writestr(executable, binary)
            bundle.writestr(root + "Info.plist", plistlib.dumps(plist, fmt=plistlib.FMT_BINARY))
            bundle.writestr(root + "wdfz.pck", pack)
            if extra:
                bundle.writestr(root + extra, b"fixture")
        digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
        info = {"passed": True, "release": True, "signed": False, "working_tree_dirty": False,
                "revision": self.sha, "platform": "ios", "sdk": "iphoneos", "architecture": "arm64",
                "package": "org.wdfz.godot", "version": RELEASE_VERSION, "build_number": RELEASE_VERSION_CODE,
                "minimum_os": "14.0", "rendering_driver": "metal", "rendering_method": "mobile",
                "vulkan_fallback": False, "packed_renderer_verified": True,
                "runtime_verified": False, "file": ipa.name, "bytes": ipa.stat().st_size, "sha256": digest}
        ipa.with_suffix(".build.json").write_text(json.dumps(info))
        ipa.with_suffix(".ipa.sha256").write_text(f"{digest}  {ipa.name}\n")
        return ipa

    def test_ipa_rejects_simulator_signatures_profiles_and_missing_game_data(self):
        for options in ({"platform": 7}, {"cpu": 0x01000007}, {"signature": True},
                        {"extra": "embedded.mobileprovision"}, {"extra": "Frameworks/F.framework/_CodeSignature/CodeResources"},
                        {"pack": b"wrong"}, {"metal": False}):
            with self.subTest(options=options):
                self.add_ios(**options)
                with self.assertRaises(ValueError):
                    validate_ios(self.folder, self.sha)

    def test_ipa_rejects_stale_source_and_file_tampering(self):
        ipa = self.add_ios()
        with self.assertRaises(ValueError):
            validate_ios(self.folder, "2" * 40)
        with ipa.open("ab") as out:
            out.write(b"modified")
        with self.assertRaises(ValueError):
            validate_ios(self.folder, self.sha)

    def test_ios_release_requires_metal_and_disabled_fallback(self):
        meta = self.add_ios().with_suffix(".build.json")
        info = json.loads(meta.read_text())
        for key, value in {"rendering_driver": "vulkan", "vulkan_fallback": True, "packed_renderer_verified": False}.items():
            with self.subTest(key=key):
                meta.write_text(json.dumps({**info, key: value}))
                with self.assertRaises(ValueError):
                    validate_ios(self.folder, self.sha)

    def test_all_three_verified_files_are_selected(self):
        self.assertEqual(len(validate_bundle(self.folder,self.sha)), 3)

    def test_unverified_or_debug_sources_are_rejected(self):
        for key, value in {"passed": False, "debug": True, "working_tree_dirty": True, "revision": "3"*40,
                           "launch_orientation": "sensor", "signing_certificate_sha256": "", "package": "org.wdfz.godot.debug"}.items():
            with self.subTest(key=key):
                self.meta.write_text(json.dumps({**self.info,key:value}))
                with self.assertRaises(ValueError): validate_bundle(self.folder,self.sha)

    def test_modified_apk_is_rejected_before_upload(self):
        self.apk.write_bytes(b"modified after verification")
        with self.assertRaises(ValueError): validate_bundle(self.folder,self.sha)

    def test_wrong_checksum_file_is_rejected(self):
        self.apk.with_suffix(".apk.sha256").write_text("not the original checksum")
        with self.assertRaises(ValueError): validate_bundle(self.folder,self.sha)

    def add_desktop(self, platform, omit="", dependency_version=None):
        name = f"wdfz-{RELEASE_VERSION}-{platform}-x86_64"
        archive = self.folder / (name + ".zip")
        info = {"revision": self.sha, "version": RELEASE_VERSION, "platform": platform,
                "release": True, "working_tree_dirty": False, "window_default": "windowed", "terracotta": terracotta.VERSION,
                "rendering_driver": "vulkan", "rendering_method": "forward_plus",
                "runtime_verified": platform == "linux", "rendering_verified": platform == "linux",
                "display_drivers_verified": ["x11", "wayland"] if platform == "linux" else []}
        with zipfile.ZipFile(archive, "w") as bundle:
            prefix = f"wdfz-{platform}/"
            binary = zipfile.ZipInfo(prefix + ("wdfz.x86_64" if platform == "linux" else "wdfz.exe"))
            binary.external_attr = 0o100755 << 16
            bundle.writestr(binary, b"synthetic executable")
            for path in ("wdfz.pck", "LICENSE", "README.txt"):
                bundle.writestr(prefix + path, b"fixture")
            bundle.writestr(prefix + "BUILD.json", json.dumps(info))
            component = "terracotta" if platform == "linux" else "terracotta.exe"
            dependencies = [component, "LICENSE", "NOTICE.md"]
            if platform == "windows": dependencies.append("VCRUNTIME140.DLL")
            for path in dependencies:
                if path != omit: bundle.writestr(prefix + "terracotta/" + path, b"dependency fixture")
            dependency = {"version": dependency_version or terracotta.VERSION, "source": terracotta.SOURCE,
                          "archive_sha256": terracotta.ASSETS[platform][1]}
            bundle.writestr(prefix + "terracotta/dependency.json", json.dumps(dependency))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        info.update(passed=True, file=archive.name, bytes=archive.stat().st_size, sha256=digest)
        archive.with_suffix(".build.json").write_text(json.dumps(info))
        archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n")
        return archive, info

    def test_release_requires_all_platforms(self):
        with self.assertRaises(FileNotFoundError): validate_all(self.folder, self.sha)
        self.add_desktop("windows")
        with self.assertRaises(FileNotFoundError): validate_all(self.folder, self.sha)
        self.add_desktop("linux")
        self.assertEqual(len(validate_all(self.folder, self.sha)), 12)
        self.add_ios().unlink()
        with self.assertRaises(FileNotFoundError): validate_all(self.folder, self.sha)

    def test_unverified_wayland_or_stale_source_blocks_publication(self):
        self.add_desktop("windows")
        archive, info = self.add_desktop("linux")
        for key, value in {"display_drivers_verified": ["x11"], "revision": "3" * 40,
                           "passed": False, "window_default": "fullscreen", "working_tree_dirty": True}.items():
            with self.subTest(key=key):
                archive.with_suffix(".build.json").write_text(json.dumps({**info, key: value}))
                with self.assertRaises(ValueError): validate_all(self.folder, self.sha)

    def test_missing_remote_component_or_runtime_blocks_publication(self):
        self.add_desktop("linux")
        for missing in ("terracotta.exe", "VCRUNTIME140.DLL", "LICENSE", "NOTICE.md"):
            with self.subTest(missing=missing):
                self.add_desktop("windows", omit=missing)
                with self.assertRaises(ValueError): validate_all(self.folder, self.sha)

    def test_wrong_remote_dependency_version_blocks_publication(self):
        self.add_desktop("linux")
        self.add_desktop("windows", dependency_version="0.0.0")
        with self.assertRaises(ValueError): validate_all(self.folder, self.sha)

    def test_desktop_tampering_and_unexpected_assets_block_publication(self):
        archive, _ = self.add_desktop("windows")
        self.add_desktop("linux")
        extra = self.folder / "unverified.apk"
        extra.touch()
        with self.assertRaises(ValueError): validate_all(self.folder, self.sha)
        extra.unlink()
        archive.write_bytes(b"modified after verification")
        with self.assertRaises(ValueError): validate_all(self.folder, self.sha)

    def test_release_version_matches_project_and_export_preset(self):
        import configparser
        root = Path(__file__).resolve().parents[2]
        project = configparser.ConfigParser(interpolation=None)
        project.read_string("[godot]\n" + (root / "project.godot").read_text())
        presets = configparser.ConfigParser(interpolation=None)
        presets.read(root / "export_presets.cfg")
        self.assertEqual(project['application']['config/version'], f'"{RELEASE_VERSION}"')
        self.assertEqual(project['application']['config/use_custom_user_dir'], 'true')
        self.assertEqual(project['application']['config/custom_user_dir_name'], '"wdfz-godot"')
        self.assertEqual(presets['preset.3.options']['version/name'], f'"{RELEASE_VERSION}"')
        self.assertEqual(int(presets['preset.3.options']['version/code']), RELEASE_VERSION_CODE)
        self.assertEqual(presets['preset.3.options']['screen/immersive_mode'], 'true')
        ios = presets['preset.4.options']
        self.assertEqual(ios['application/version'], f'"{RELEASE_VERSION_CODE}"')
        self.assertEqual(ios['application/short_version'], '""')  # inherits project version
        self.assertEqual(ios['application/bundle_identifier'], '"org.wdfz.godot"')
        self.assertEqual(ios['application/export_project_only'], 'true')

    def test_draft_only_uploads_and_verifies_but_never_publishes(self):
        # 2026-11-14: the release workflow defaults to stopping at a verified draft.
        import os
        import publish_release
        from unittest.mock import patch
        self.add_desktop("linux")
        self.add_desktop("windows")
        files = validate_all(self.folder, self.sha)
        notes_dir = tempfile.TemporaryDirectory()
        self.addCleanup(notes_dir.cleanup)
        notes = Path(notes_dir.name) / "notes.md"
        notes.write_text("notes")
        uploaded = {}
        calls = []

        def release():
            return {"id": 7, "draft": True, "prerelease": False, "target_commitish": self.sha, "html_url": "https://example.invalid/r/7",
                    "assets": [{"name": n, "state": "uploaded", "size": s, "digest": d} for n, (s, d) in uploaded.items()]}

        class Done:
            def __init__(self, out="", code=0, err=""):
                self.stdout, self.returncode, self.stderr = out, code, err

        def run(command, **_kwargs):
            calls.append(command)
            if command[:3] == ["gh", "api", "repos/fixture/game/git/ref/tags/v" + RELEASE_VERSION]:
                return Done(code=1, err="(HTTP 404)")
            if command[:3] == ["gh", "release", "view"]:
                return Done(json.dumps({"apiUrl": "https://api.example.invalid/releases/7"}))
            if command[:3] == ["gh", "release", "upload"]:
                for path in command[6:]:
                    p = Path(path)
                    uploaded[p.name] = (p.stat().st_size, "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest())
                return Done()
            if command[:2] == ["gh", "api"]:
                return Done(json.dumps(release()))
            return Done()

        argv = ["publish_release.py", "--assets", str(self.folder), "--tag", "v" + RELEASE_VERSION, "--notes", str(notes), "--draft-only"]
        with patch.dict(os.environ, {"GITHUB_SHA": self.sha, "GITHUB_REPOSITORY": "fixture/game"}), \
             patch.object(sys, "argv", argv), patch.object(publish_release.subprocess, "run", side_effect=run), \
             patch.object(publish_release.ios_bundle, "verify_packed_renderer") as verify_renderer:
            publish_release.main()
        verify_renderer.assert_called_once()
        self.assertEqual(set(uploaded), {f.name for f in files})
        self.assertFalse(any(c[:3] == ["gh", "release", "edit"] for c in calls), "a draft-only run never publishes")
