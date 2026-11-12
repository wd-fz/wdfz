import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from ci import terracotta_android


class TerracottaBuildTests(unittest.TestCase):
    def test_injection_preserves_launcher_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'android_source.zip'
            manifest = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<uses-permission android:name="android.permission.INTERNET"/>
<application android:allowBackup="false"><activity android:name=".GodotApp" android:screenOrientation="userLandscape"/></application>
</manifest>'''
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('build.gradle', '// official template fixture')
                bundle.writestr('gradlew', '#!/bin/sh\n')
                bundle.writestr('src/main/AndroidManifest.xml', manifest)
            template = root / 'android-project'
            terracotta_android.install_template(template, archive, '4.6.3.stable')
            library = root / 'libterracotta.so'
            library.write_bytes(b'fixture native library')
            for _ in range(2): terracotta_android.install(ROOT, template, library)
            final = ET.parse(template / 'build/src/main/AndroidManifest.xml').getroot()
            key = lambda value: '{http://schemas.android.com/apk/res/android}' + value
            app = final.find('application')
            self.assertEqual(app.get(key('allowBackup')), 'false')
            self.assertEqual(app.find('activity').get(key('screenOrientation')), 'userLandscape')
            self.assertEqual(len(app.findall('service')), 1)
            service = app.find('service')
            self.assertEqual(service.get(key('exported')), 'false')
            self.assertEqual(service.get(key('permission')), 'android.permission.BIND_VPN_SERVICE')
            self.assertEqual(len(final.findall('uses-permission')), 3)
            for variant in ('debug', 'release'):
                self.assertEqual((template / f'build/libs/{variant}/arm64-v8a/libterracotta.so').read_bytes(), library.read_bytes())
            self.assertEqual((template / '.build_version').read_text(), '4.6.3.stable\n')
            self.assertEqual((template / 'build/build.gradle').read_text().count('android.sourceSets.main.assets.srcDirs'), 1)
            self.assertTrue((template / 'build/terracotta_assets/terracotta/LICENSE').is_file())

    def test_template_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('build.gradle', '')
                bundle.writestr('../outside', '')
            with self.assertRaises(RuntimeError):
                terracotta_android.install_template(root / 'target', archive, '4.6.3.stable')
            self.assertFalse((root / 'target/outside').exists())
