import struct
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from export_android import verify_launcher_orientation, verify_manifest, verify_vulkan_manifest, verify_fullscreen_launch


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
    def test_android_requires_vulkan_and_exports_mobile_renderer(self):
        tree = '''E: manifest
  E: uses-feature
    A: android:name(0x01010003)="android.hardware.vulkan.version"
    A: android:version(0x01010519)=(type 0x11)0x400003
    A: android:required(0x0101028e)=(type 0x12)0xffffffff
  E: application
    E: meta-data
      A: android:name(0x01010003)="org.godotengine.rendering.method"
      A: android:value(0x01010024)="mobile"
'''
        self.assertTrue(verify_vulkan_manifest(tree)["vulkan_required"])
        for bad in [tree.replace("0xffffffff", "0x0"), tree.replace("0x400003", "0x0"),
                    tree.replace("android.hardware.vulkan.version", "android.hardware.other"),
                    tree.replace('(type 0x12)0xffffffff', '"false"'),
                    tree.replace("android:required", "android:other"),
                    tree.replace('="mobile"', '="gl_compatibility"'), ""]:
            with self.subTest(tree=bad), self.assertRaises(RuntimeError):
                verify_vulkan_manifest(bad)

    def test_godot_launcher_alias_checks_the_target_activity(self):
        tree = '''E: manifest
  A: package="org.wdfz.godot"
  E: application
    E: activity
      A: android:name(0x01010003)="org.wdfz.godot.GodotApp"
      A: android:screenOrientation(0x0101001e)=(type 0x10)0xb
    E: activity-alias
      A: android:name(0x01010003)=".GodotAppLauncher"
      A: android:targetActivity(0x01010202)=".GodotApp"
      E: intent-filter
        E: action
          A: android:name(0x01010003)="android.intent.action.MAIN"
        E: category
          A: android:name(0x01010003)="android.intent.category.LAUNCHER"
'''
        self.assertEqual(verify_launcher_orientation(tree), "userLandscape")
        for bad in [tree.replace("0xb", "0xa"), tree.replace('=".GodotApp"','=".Missing"'), tree.replace("android:targetActivity", "android:other")]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                verify_launcher_orientation(bad)

    def test_public_release_must_not_be_debuggable(self):
        manifest = "package: name='org.wdfz.godot' versionCode='2' versionName='0.2.0'\nsdkVersion:'24'\ntargetSdkVersion:'36'\nnative-code: 'arm64-v8a'\n"
        verify_manifest(manifest,True)
        for bad in [manifest+"application-debuggable", manifest.replace("0.2.0","0.1-debug"), manifest.replace("org.wdfz.godot'","org.wdfz.godot.debug'"), manifest.replace("arm64-v8a","x86")]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                verify_manifest(bad,True)

    def test_actual_launcher_is_user_landscape(self):
        self.assertEqual(verify_launcher_orientation(activity("0xb")), "userLandscape")

    def test_unrestricted_or_portrait_launch_is_rejected(self):
        for value in ["0xa", "0xd", "0x1", "0x7"]:
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                verify_launcher_orientation(activity(value))

    def test_other_landscape_activity_does_not_hide_bad_launcher(self):
        with self.assertRaises(RuntimeError):
            verify_launcher_orientation(activity("0xb",False) + activity("0xa"))

    def test_missing_attribute_or_ambiguous_launcher_is_rejected(self):
        for tree in ["", activity("0xb") * 2, activity("0xb").replace("android:screenOrientation", "android:other")]:
            with self.subTest(tree=tree), self.assertRaises(RuntimeError):
                verify_launcher_orientation(tree)


if __name__ == "__main__":
    unittest.main()


class FullscreenLaunchTests(unittest.TestCase):
    @staticmethod
    def arguments(*values):
        return struct.pack('<I', len(values)) + b''.join(struct.pack('<I', len(v.encode())) + v.encode() for v in values)

    def test_fullscreen_export(self):
        self.assertTrue(verify_fullscreen_launch(self.arguments('--fullscreen', '--xr-mode', 'off')))

    def test_windowed_missing_or_malformed_launch_arguments(self):
        for raw in [self.arguments('--fullscreen', '--windowed'), self.arguments('--xr-mode', 'off'),
                    b'', self.arguments('--fullscreen')[:-1], self.arguments('--fullscreen') + b'trailing']:
            with self.subTest(raw=raw):
                with self.assertRaises(RuntimeError): verify_fullscreen_launch(raw)
