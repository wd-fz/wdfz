import configparser
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from ci import package_budget


class PackageBudgetTests(unittest.TestCase):
    def test_every_platform_excludes_retired_models_and_editor_code(self):
        root = Path(__file__).resolve().parents[2]
        presets = configparser.ConfigParser(interpolation=None)
        presets.read(root / "export_presets.cfg")
        for section in presets.sections():
            if section.endswith(".options"): continue
            with self.subTest(preset=section):
                filters = presets[section]["exclude_filter"]
                self.assertIn("assets/campus_q4/*", filters)
                self.assertIn("addons/*", filters)

    def test_report_requires_verified_non_growing_resources(self):
        report = {"policy": package_budget.POLICY, "scenes": 2, "lossless_verified": 2,
                  "exterior_tiers": [0, 1, 2, 3], "exterior_bytes": 250,
                  "scene_bytes_before": 2000, "scene_bytes_after": 1000,
                  "textures": 3, "unique_textures": 1, "texture_bytes_before": 300, "texture_bytes_after": 100}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            directory = root / "build/reports/package-size"
            directory.mkdir(parents=True)
            path = directory / "game.apk.json"
            path.write_text(json.dumps(report))
            self.assertEqual(package_budget.read_report(root, Path("game.apk")), report)
            for bad in ({"exterior_tiers": [0, 1, 2]}, {"lossless_verified": 1}, {"scene_bytes_after": 2001}, {"unique_textures": 4}, {"policy": {}}):
                with self.subTest(bad=bad):
                    path.write_text(json.dumps({**report, **bad}))
                    with self.assertRaises(RuntimeError): package_budget.read_report(root, Path("game.apk"))
            package_budget.clear_report(root, Path("game.apk"))
            self.assertFalse(path.exists(), "a previous export report cannot satisfy the next build")

    def test_apk_requires_real_optimized_assets_and_no_retired_directory(self):
        for retired in (False, True):
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, "w") as archive:
                archive.writestr("assets/assets/package_policy.json", json.dumps(package_budget.POLICY))
                archive.writestr("assets/assets/campus/scenes/teach1.glb.packed.scn", b"fixture")
                archive.writestr("assets/assets/packed_textures/fixture.ctex", b"fixture")
                for tier in package_budget.POLICY["model_tiers"]:
                    archive.writestr(f"assets/assets/campus/resident/out_{tier}.scn", b"fixture")
                if retired: archive.writestr("assets/assets/campus_q4/scenes/out.glb", b"retired")
            with zipfile.ZipFile(stream) as archive:
                if retired:
                    with self.assertRaisesRegex(RuntimeError, "retired"): package_budget.verify_apk(archive)
                else: package_budget.verify_apk(archive)
