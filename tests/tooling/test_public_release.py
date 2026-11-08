import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from publish_android_release import validate_bundle


class PublicReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.apk = self.folder / "wdfz-0.1.0-android-arm64.apk"
        self.apk.write_bytes(b"synthetic checksum fixture")
        self.sha = "1" * 40
        digest = hashlib.sha256(self.apk.read_bytes()).hexdigest()
        self.info = {"passed": True, "debug": False, "working_tree_dirty": False, "revision": self.sha,
                     "package": "org.wdfz.godot", "version": "0.1.0", "version_code": 1,
                     "abi": "arm64-v8a", "min_sdk": 24, "target_sdk": 36, "page_alignment": 16384,
                     "launch_orientation": "userLandscape", "file": self.apk.name,
                     "signing_certificate_sha256": "2"*64, "sha256": digest, "bytes": self.apk.stat().st_size}
        self.meta = self.apk.with_suffix(".build.json")
        self.meta.write_text(json.dumps(self.info))
        self.apk.with_suffix(".apk.sha256").write_text(f"{digest}  {self.apk.name}\n")

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
