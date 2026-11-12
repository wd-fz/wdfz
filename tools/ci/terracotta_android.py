"""Inject the source plugin into Godot's official, disposable Gradle build template."""
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET


def install(root: Path, template: Path, library: Path):
    project = template / 'build'
    if not (project / 'build.gradle').is_file():
        raise RuntimeError('Official Android Gradle template is missing')
    source = root / 'platform/android/terracotta/src'
    # Official template uses standard src/main/java; no custom engine build needed.
    shutil.copytree(source, project / 'src/main/java', dirs_exist_ok=True)
    for variant in ('debug', 'release'):
        destination = project / 'libs' / variant / 'arm64-v8a'
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(library, destination / 'libterracotta.so')
    notices = project / 'src/main/assets/terracotta'
    notices.mkdir(parents=True, exist_ok=True)
    for name in ('LICENSE', 'NOTICE.md'):
        shutil.copy2(root / 'third_party/terracotta' / name, notices / name)
    manifest = project / 'src/main/AndroidManifest.xml'
    android = 'http://schemas.android.com/apk/res/android'
    ET.register_namespace('android', android)
    ET.register_namespace('tools', 'http://schemas.android.com/tools')
    key = lambda value: '{' + android + '}' + value
    tree = ET.parse(manifest)
    main = tree.getroot()
    existing = {node.get(key('name')) for node in main.findall('uses-permission')}
    for permission in ('FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_SPECIAL_USE'):
        name = 'android.permission.' + permission
        if name not in existing: ET.SubElement(main, 'uses-permission', {key('name'): name})
    application = main.find('application')
    for node in list(application):
        if node.get(key('name')) in ('org.godotengine.plugin.v2.WdfzTerracotta', 'org.wdfz.terracotta.TerracottaVpnService'):
            application.remove(node)
    ET.SubElement(application, 'meta-data', {key('name'): 'org.godotengine.plugin.v2.WdfzTerracotta', key('value'): 'org.wdfz.terracotta.WdfzTerracotta'})
    service = ET.SubElement(application, 'service', {
        key('name'): 'org.wdfz.terracotta.TerracottaVpnService', key('exported'): 'false',
        key('permission'): 'android.permission.BIND_VPN_SERVICE', key('foregroundServiceType'): 'specialUse'})
    ET.SubElement(ET.SubElement(service, 'intent-filter'), 'action', {key('name'): 'android.net.VpnService'})
    ET.SubElement(service, 'property', {key('name'): 'android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE',
        key('value'): 'User initiated peer-to-peer game VPN limited to this application'})
    tree.write(manifest, encoding='utf-8', xml_declaration=True)


def verify(tree, names):
    for entry in ('org.godotengine.plugin.v2.WdfzTerracotta', 'org.wdfz.terracotta.TerracottaVpnService',
                  'android.permission.BIND_VPN_SERVICE', 'android.permission.FOREGROUND_SERVICE_SPECIAL_USE'):
        if entry not in tree: raise RuntimeError('APK Terracotta manifest entry missing: ' + entry)
    for entry in ('lib/arm64-v8a/libterracotta.so', 'assets/terracotta/LICENSE', 'assets/terracotta/NOTICE.md'):
        if entry not in names: raise RuntimeError('APK Terracotta resource missing: ' + entry)
