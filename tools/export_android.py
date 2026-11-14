#!/usr/bin/env python3
"""Export and verify Android APKs with Godot's official Gradle template and prebuilt engine."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import zipfile
from ci import quality
from ci.common import ENGINE, ROOT, check_version, run
from ci import terracotta_android
import terracotta

BUILD_TOOLS = "36.0.0"
PACKAGE = "org.wdfz.godot.debug"
RELEASE_PACKAGE = "org.wdfz.godot"
RELEASE_VERSION = "0.4.0"
RELEASE_VERSION_CODE = 5


def verify_fullscreen_launch(raw):
    """The Android export must enter immersive mode before the first scene loads."""
    try:
        count = struct.unpack_from('<I', raw)[0]
        offset, arguments = 4, []
        for _ in range(count):
            length = struct.unpack_from('<I', raw, offset)[0]
            offset += 4
            if offset + length > len(raw): raise ValueError('Truncated launch argument')
            arguments.append(raw[offset:offset + length].decode('utf-8'))
            offset += length
        if offset != len(raw): raise ValueError('Trailing launch data')
    except (struct.error, UnicodeError, ValueError) as error:
        raise RuntimeError('Invalid Android launch arguments') from error
    if '--fullscreen' not in arguments or '--windowed' in arguments:
        raise RuntimeError('Android must launch in immersive fullscreen')
    return True


def verify_manifest(manifest, release=False):
    package = RELEASE_PACKAGE if release else PACKAGE
    for expected in (f"package: name='{package}'", "sdkVersion:'24'", "targetSdkVersion:'36'", "native-code: 'arm64-v8a'", "uses-permission: name='android.permission.INTERNET'", "uses-permission: name='android.permission.CHANGE_WIFI_MULTICAST_STATE'"):
        if expected not in manifest:
            raise RuntimeError(f"APK manifest did not confirm {expected}")
    if ("application-debuggable" in manifest) == release:
        raise RuntimeError("APK debuggable flag does not match the requested build type")
    if release and (f"versionName='{RELEASE_VERSION}'" not in manifest or f"versionCode='{RELEASE_VERSION_CODE}'" not in manifest):
        raise RuntimeError("APK release version does not match the release preset")


def verify_launcher_orientation(tree):
    """Check the launch activity, not an unrelated activity or a runtime setting."""
    lines = tree.splitlines()
    entries = []
    for index, line in enumerate(lines):
        activity = re.match(r"^( *)E: (activity(?:-alias)?)(?: |$)", line)
        if not activity:
            continue
        indent = len(activity[1])
        block = []
        attributes = []
        nested = False
        for child in lines[index + 1:]:
            if child.strip() and len(child) - len(child.lstrip()) <= indent:
                break
            block.append(child)
            nested |= child.lstrip().startswith("E:")
            if not nested:
                attributes.append(child)
        text = "\n".join(block)
        entries.append({"kind": activity[2], "attributes": "\n".join(attributes),
                        "launcher": '"android.intent.action.MAIN"' in text and '"android.intent.category.LAUNCHER"' in text})
    launchers = [entry for entry in entries if entry["launcher"]]
    if len(launchers) != 1:
        raise RuntimeError("APK must have exactly one verifiable launcher activity")
    launcher = launchers[0]
    if launcher["kind"] == "activity-alias":
        # Godot 4.6 launches through GodotAppLauncher; orientation belongs to its target.
        package_match = re.search(r'A: package="([^"]+)"', tree)
        package = package_match[1] if package_match else ""

        def attribute(entry, name):
            value = re.search(r'android:' + name + r'\([^)]*\)="([^"]+)"', entry["attributes"])
            if not value: return ""
            name = value[1]
            return package + name if name.startswith(".") else package + "." + name if "." not in name else name

        target = attribute(launcher, "targetActivity")
        targets = [entry for entry in entries if entry["kind"] == "activity" and attribute(entry, "name") == target]
        if not target or len(targets) != 1:
            raise RuntimeError("Launcher alias must resolve to exactly one declared activity")
        launcher = targets[0]
    # Pinned Godot 4.6.3 maps SCREEN_SENSOR_LANDSCAPE to Android USER_LANDSCAPE (11).
    # See platform/android/export/gradle_export_util.cpp in the official engine tag.
    orientation = re.search(r"android:screenOrientation\([^)]*\)=\(type 0x10\)(0x[0-9a-fA-F]+)", launcher["attributes"])
    if not orientation or int(orientation[1], 16) != 11:
        raise RuntimeError("APK launcher must declare userLandscape (11) before Godot starts")
    return "userLandscape"


def verify_vulkan_manifest(tree):
    """Verify what Android receives, including the renderer's exported mobile override."""
    lines = tree.splitlines()
    features, metadata = {}, {}
    for index, line in enumerate(lines):
        element = re.match(r"^( *)E: (uses-feature|meta-data)(?: |$)", line)
        if not element:
            continue
        block = []
        for child in lines[index + 1:]:
            if child.strip() and len(child) - len(child.lstrip()) <= len(element[1]):
                break
            block.append(child)
        text = "\n".join(block)
        name = re.search(r'android:name\([^)]*\)="([^"]+)"', text)
        if name:
            (features if element[2] == "uses-feature" else metadata)[name[1]] = text
    feature = features.get("android.hardware.vulkan.version", "")
    version = re.search(r"android:version\([^)]*\)=\(type 0x1[01]\)(0x[0-9a-fA-F]+)", feature)
    required = re.search(r"android:required\([^)]*\)=\(type 0x12\)(0x[0-9a-fA-F]+)", feature)
    if not version or int(version[1], 16) < 0x400003 or not required or int(required[1], 16) != 0xffffffff:
        raise RuntimeError("APK must require Vulkan hardware; an optional or missing feature permits unsupported devices")
    renderer = metadata.get("org.godotengine.rendering.method", "")
    if not re.search(r'android:value\([^)]*\)="mobile"', renderer):
        raise RuntimeError("APK must export the Mobile renderer for Android")
    return {"rendering_driver": "vulkan", "rendering_method": "mobile", "vulkan_required": True,
            "vulkan_version_encoded": int(version[1], 16)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", default=os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT"))
    parser.add_argument("--jdk", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--keystore", type=Path)
    parser.add_argument("--release", action="store_true", help="sign with ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD and --keystore")
    args = parser.parse_args()
    if not sys.platform.startswith("linux"):
        raise RuntimeError("This automation runs on Linux; use the Android Debug preset in Godot on other systems")
    if not args.sdk:
        raise RuntimeError("Set ANDROID_HOME or pass --sdk with platform-tools and build-tools;36.0.0 installed")
    sdk = Path(args.sdk).expanduser().resolve()
    java = shutil.which("java")
    jdk = Path(args.jdk).expanduser().resolve() if args.jdk else Path(java).resolve().parents[1] if java else None
    suffix = ".exe" if os.name == "nt" else ""
    build_tools = sdk / "build-tools" / BUILD_TOOLS
    if jdk is None or any(not (jdk / "bin" / (tool + suffix)).is_file() for tool in ("java", "javac", "keytool")):
        raise RuntimeError("A full JDK with java, javac and keytool is required by Gradle; pass --jdk or set JAVA_HOME")
    for name in ("aapt" + suffix, "zipalign" + suffix, "apksigner.bat" if os.name == "nt" else "apksigner"):
        if not (build_tools / name).is_file():
            raise RuntimeError(f"Missing Android build tool: {build_tools / name}")
    if not (sdk / "platform-tools" / ("adb" + suffix)).is_file():
        raise RuntimeError("Android SDK platform-tools are missing")
    if not (sdk / "platforms/android-36/android.jar").is_file():
        raise RuntimeError("Android SDK platforms;android-36 is required by the Gradle export template")

    if args.release:
        if not args.keystore or not args.keystore.is_file():
            raise RuntimeError("Release requires an existing signing keystore; no fallback debug key is allowed")
        if not os.environ.get("ANDROID_KEY_ALIAS") or not os.environ.get("ANDROID_KEY_PASSWORD"):
            raise RuntimeError("Release requires ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD")
    reports = ROOT / ("build/reports/android-release" if args.release else "build/reports/android")
    reports.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    summary = {"passed": False, "package": RELEASE_PACKAGE if args.release else PACKAGE, "runtime_verified": False,
               "build_system": "gradle"}
    try:
        print(quality.check(ROOT), flush=True)
        summary["engine"] = check_version(reports)
        # An isolated editor configuration avoids replacing a developer's Android settings.
        config = ROOT / "build/android-editor"
        settings = config / "godot" / ("editor_settings-" + ".".join((ROOT / ".godot-version").read_text().strip().split(".")[:2]) + ".tres")
        settings.parent.mkdir(parents=True, exist_ok=True)
        keystore = (args.keystore or Path.home() / ".android/wdfz-debug.keystore").expanduser().resolve()
        keystore.parent.mkdir(parents=True, exist_ok=True)
        if not args.release and not keystore.exists():
            run("debug-key", [str(jdk / "bin" / ("keytool" + suffix)), "-genkeypair", "-noprompt",
                "-keystore", str(keystore), "-storetype", "JKS", "-storepass", "android", "-keypass", "android",
                "-alias", "androiddebugkey", "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
                "-dname", "CN=Android Debug,O=Android,C=US"], reports, timeout=60)
            keystore.chmod(0o600)
        values = {"android_sdk_path": str(sdk), "java_sdk_path": str(jdk)}
        if not args.release:
            values.update(debug_keystore=str(keystore), debug_keystore_user="androiddebugkey", debug_keystore_pass="android")
        settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' +
            "".join("export/android/" + key + " = " + json.dumps(value) + "\n" for key, value in values.items()), encoding="utf-8")
        env = {**os.environ, "XDG_CONFIG_HOME": str(config), "JAVA_HOME": str(jdk)}
        run("import", [ENGINE, "--headless", "--path", str(ROOT), "--editor", "--import"], reports, timeout=900, env=env)
        packages = ROOT / "build/packages"
        packages.mkdir(parents=True, exist_ok=True)
        apk = packages / (f"wdfz-{RELEASE_VERSION}-android-arm64.apk" if args.release else "wdfz-android-debug-arm64.apk")
        apk.unlink(missing_ok=True)
        unsigned = packages / ".release-unsigned.apk" if args.release else apk
        # The 4.6.3 non-Gradle exporter writes Vulkan feature booleans/versions as
        # strings. Use Android's manifest compiler rather than weaken validation.
        template = ROOT / "build/android-project"
        installed = template / ".build_version"
        expected = (ROOT / ".godot-version").read_text().strip() + ".stable"
        if installed.exists() and installed.read_text().strip() != expected:
            shutil.rmtree(template)
        if not (template / "build/build.gradle").exists():
            data_home = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
            source_zip = data_home / 'godot/export_templates' / expected / 'android_source.zip'
            terracotta_android.install_template(template, source_zip, expected)
        terracotta_android.install(ROOT, template, terracotta.prepare('android'))
        summary['terracotta'] = terracotta.VERSION
        run("export-android", [ENGINE, "--headless", "--path", str(ROOT), "--export-release" if args.release else "--export-debug",
                              "Android Release" if args.release else "Android Debug", str(unsigned)],
            reports, timeout=900, env=env)
        signer = build_tools / ("apksigner.bat" if os.name == "nt" else "apksigner")
        if args.release:
            aligned = packages / ".release-aligned.apk"
            run("align-release", [str(build_tools / "zipalign"), "-f", "-P", "16", "4", str(unsigned), str(aligned)], reports)
            # Passwords stay in the environment, never in arguments, preset files or build reports.
            run("sign-release", [str(signer), "sign", "--ks", str(keystore), "--ks-key-alias", env["ANDROID_KEY_ALIAS"],
                "--ks-pass", "env:ANDROID_KEY_PASSWORD", "--key-pass", "env:ANDROID_KEY_PASSWORD", "--v4-signing-enabled", "false", "--out", str(apk), str(aligned)], reports, env=env)
            unsigned.unlink()
            aligned.unlink()
        signature = run("signature", [str(signer), "verify", "--verbose", "--print-certs", str(apk)], reports, env=env)
        if args.release:
            match = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})", signature)
            if not match:
                raise RuntimeError("Release signature certificate digest is missing")
            summary.update(version=RELEASE_VERSION, version_code=RELEASE_VERSION_CODE, signing_certificate_sha256=match[1].lower())
        run("alignment", [str(build_tools / ("zipalign" + suffix)), "-c", "-P", "16", "-v", "4", str(apk)], reports)
        manifest = run("manifest", [str(build_tools / ("aapt" + suffix)), "dump", "badging", str(apk)], reports)
        verify_manifest(manifest,args.release)
        manifest_tree = run("manifest-tree", [str(build_tools / ("aapt" + suffix)), "dump", "xmltree", str(apk), "AndroidManifest.xml"], reports)
        summary["launch_orientation"] = verify_launcher_orientation(manifest_tree)
        summary.update(verify_vulkan_manifest(manifest_tree))
        with zipfile.ZipFile(apk) as archive:
            summary['fullscreen_forced'] = verify_fullscreen_launch(archive.read('assets/_cl_'))
            names = archive.namelist()
            terracotta_android.verify(manifest_tree, names)
            entries = set(names)
            if archive.testzip() is not None:
                raise RuntimeError("APK contains a corrupt ZIP entry")
            for required in ("lib/arm64-v8a/libgodot_android.so", "assets/project.binary", "assets/assets/audio/index.json"):
                if required not in names:
                    raise RuntimeError(f"APK is missing {required}")
            if any(name.startswith(tuple("assets/" + folder + "/" for folder in ("tests", "tools", "docs", "pictures"))) for name in names):
                raise RuntimeError("APK includes development files")
            # Vulkan also supports portable lossless textures. Check the exported
            # remaps instead of incorrectly requiring every image to be ETC2/ASTC.
            remaps = 0
            for name in names:
                if not name.endswith((".import", ".remap")):
                    continue
                text = archive.read(name).decode("utf-8").rstrip("\0")
                for ref in re.findall(r'^path(?:\.\w+)?="res://([^"\n]+)"', text, re.M):
                    if "assets/" + ref not in entries:
                        raise RuntimeError(f"APK import points to a missing resource: {ref}")
                    if ref.endswith((".s3tc.ctex", ".bptc.ctex")):
                        raise RuntimeError(f"APK references a desktop-only texture: {ref}")
                    remaps += 1
            textures = sum(name.endswith(".ctex") for name in names)
            if not remaps or not textures:
                raise RuntimeError("APK is missing imported runtime resources")
            # ZIP alignment alone does not establish 16 KB support: validate the
            # ELF load segments too, including libraries compressed in the APK.
            libraries = [name for name in names if name.startswith("lib/arm64-v8a/") and name.endswith(".so")]
            for name in libraries:
                with archive.open(name) as source:
                    header = source.read(64)
                    if header[:6] != b"\x7fELF\x02\x01" or struct.unpack_from("<H", header, 18)[0] != 183:
                        raise RuntimeError(f"Not an ARM64 little-endian ELF library: {name}")
                    offset = struct.unpack_from("<Q", header, 32)[0]
                    size, count = struct.unpack_from("<HH", header, 54)
                    source.seek(offset)
                    segments = source.read(size * count)
                    loads = 0
                    for index in range(count):
                        at = index * size
                        if struct.unpack_from("<I", segments, at)[0] != 1:
                            continue
                        loads += 1
                        file_offset, address = struct.unpack_from("<QQ", segments, at + 8)
                        alignment = struct.unpack_from("<Q", segments, at + 48)[0]
                        if alignment < 16384 or (address - file_offset) % 16384:
                            raise RuntimeError(f"Native library is not 16 KB page compatible: {name}")
                    if not loads:
                        raise RuntimeError(f"Native library has no loadable segments: {name}")
            summary.update(imported_resources=remaps, textures=textures, native_libraries=len(libraries), page_alignment=16384)
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())
        sha = hashlib.sha256()
        with apk.open("rb") as source:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                sha.update(block)
        digest = sha.hexdigest()
        summary.update(passed=True, revision=revision, working_tree_dirty=dirty, file=apk.name,
                       bytes=apk.stat().st_size, sha256=digest, abi="arm64-v8a", min_sdk=24, target_sdk=36, debug=not args.release)
        apk.with_suffix(".apk.sha256").write_text(f"{digest}  {apk.name}\n")
        apk.with_suffix(".build.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(f"ANDROID {'RELEASE' if args.release else 'DEBUG'}: verified {apk.relative_to(ROOT)} ({apk.stat().st_size / 1024 / 1024:.1f} MiB)", flush=True)
    finally:
        (reports / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
