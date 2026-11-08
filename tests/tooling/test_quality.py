from contextlib import redirect_stdout
import io
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from ci.quality import code_only, rule_errors
from ci.common import run


class BoundaryTests(unittest.TestCase):
    def test_helpers_are_rules_too(self):
        self.assertTrue(rule_errors("game/features/story/helper.gd", "extends RefCounted\nvar data = FileAccess.open('x', 1)", {}))

    def test_indirect_adapter_dependency(self):
        self.assertTrue(rule_errors("game/features/story/dread.gd", 'var scale = CampusData.layout("out")',
                                    {"CampusData": "game/infrastructure/content/campus_data.gd"}))

    def test_core_cannot_depend_on_a_feature(self):
        self.assertTrue(rule_errors("game/core/session/session.gd", "var module: InventoryModule",
                                    {"InventoryModule": "game/features/items/inventory_module.gd"}))

    def test_comments_strings_and_multiline_literals_are_not_dependencies(self):
        source = '# FileAccess\nvar label = "Input # get_tree()"\nvar s = """Node\nCampusData"""\n'
        self.assertEqual(rule_errors("game/features/demo/example.gd", source, {}), [])
        self.assertEqual(code_only(source).count("\n"), source.count("\n"))

    def test_zero_exit_with_script_error_fails(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError):
                run("printed-error", [sys.executable, "-c", "print('SCRIPT ERROR: parse failed')"], Path(directory))

    def test_nonzero_exit_fails_and_retains_log(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError):
                run("exit-error", [sys.executable, "-c", "print('diagnostic'); exit(2)"], Path(directory))
            self.assertIn("diagnostic", (Path(directory) / "exit-error.log").read_text())

    def test_printed_error_stops_a_process_that_does_not_exit(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "printed an engine error"):
                run("stuck-script", [sys.executable, "-c",
                    "import time; print('SCRIPT ERROR: parse failed', flush=True); time.sleep(30)"],
                    Path(directory), timeout=3)


if __name__ == "__main__":
    unittest.main()
