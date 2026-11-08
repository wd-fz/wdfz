import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from export_android import verify_launcher_orientation, verify_manifest


def activity(orientation, launcher=True):
    return f'''    E: activity (line=20)
      A: android:name(0x01010003)="com.godot.game.GodotApp"
      A: android:screenOrientation(0x0101001e)=(type 0x10){orientation}
      E: intent-filter (line=30)
        E: action (line=31)
          A: android:name(0x01010003)="android.intent.action.MAIN"
        E: category (line=32)
          A: android:name(0x01010003)="android.intent.category.{"LAUNCHER" if launcher else "DEFAULT"}"
'''


class AndroidManifestTests(unittest.TestCase):
    def test_godot_launcher_alias_checks_the_target_activity(self):
        tree = '''E: manifest
  A: package="org.wdfz.godot"
  E: application
    E: activity
      A: android:name(0x01010003)="org.wdfz.godot.GodotApp"
      A: android:screenOrientation(0x0101001e)=(type 0x10)0x6
    E: activity-alias
      A: android:name(0x01010003)=".GodotAppLauncher"
      A: android:targetActivity(0x01010202)=".GodotApp"
      E: intent-filter
        E: action
          A: android:name(0x01010003)="android.intent.action.MAIN"
        E: category
          A: android:name(0x01010003)="android.intent.category.LAUNCHER"
'''
        self.assertEqual(verify_launcher_orientation(tree), "sensorLandscape")
        for bad in [tree.replace("0x6", "0xa"), tree.replace('=".GodotApp"','=".Missing"'), tree.replace("android:targetActivity", "android:other")]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                verify_launcher_orientation(bad)

    def test_public_release_must_not_be_debuggable(self):
        manifest = "package: name='org.wdfz.godot' versionCode='1' versionName='0.1.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\nnative-code: 'arm64-v8a'\n"
        verify_manifest(manifest,True)
        for bad in [manifest+"application-debuggable", manifest.replace("0.1.0","0.1-debug"), manifest.replace("org.wdfz.godot'","org.wdfz.godot.debug'"), manifest.replace("arm64-v8a","x86")]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                verify_manifest(bad,True)

    def test_actual_launcher_is_sensor_landscape(self):
        self.assertEqual(verify_launcher_orientation(activity("0x6")), "sensorLandscape")

    def test_unrestricted_or_portrait_launch_is_rejected(self):
        for value in ["0xa", "0x1", "0x7"]:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                verify_launcher_orientation(activity(value))

    def test_other_landscape_activity_does_not_hide_bad_launcher(self):
        with self.assertRaises(RuntimeError):
            verify_launcher_orientation(activity("0x6",False) + activity("0xa"))

    def test_missing_attribute_or_ambiguous_launcher_is_rejected(self):
        for tree in ["", activity("0x6") * 2, activity("0x6").replace("android:screenOrientation", "android:other")]:
            with self.subTest(tree=tree), self.assertRaises(RuntimeError):
                verify_launcher_orientation(tree)


if __name__ == "__main__":
    unittest.main()
