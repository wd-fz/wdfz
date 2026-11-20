"""Inspect the shipping IPA itself on either macOS or the Linux release runner."""
import plistlib
import shutil
import stat
import struct
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from ci.common import ENGINE, ROOT, run

BUNDLE_ID = "org.wdfz.godot"
MINIMUM_OS = "14.0"
APP = "Payload/wdfz.app/"
LANDSCAPE = {"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
MACH64 = b"\xcf\xfa\xed\xfe"
MACH_MAGICS = {MACH64, b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf",
               b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def inspect_macho(stream, executable):
    """Read only the Mach-O header and load commands. arm64 also exists on simulators."""
    header = stream.read(32)
    if len(header) != 32 or header[:4] != MACH64:
        raise ValueError("IPA needs a thin 64-bit device binary")
    _, cpu, _, kind, count, size, _, _ = struct.unpack("<8I", header)
    if cpu != 0x0100000C or (executable and kind != 2):
        raise ValueError("IPA binary is not an ARM64 device executable")
    if size > 16 * 1024 * 1024 or count > size // 8:
        raise ValueError("Invalid Mach-O command table")
    commands = stream.read(size)
    offset = 0
    device = False
    metal = False
    for _ in range(count):
        if offset + 8 > len(commands):
            raise ValueError("Truncated Mach-O command")
        cmd, length = struct.unpack_from("<II", commands, offset)
        if length < 8 or offset + length > len(commands):
            raise ValueError("Invalid Mach-O command length")
        if cmd == 0x1D:  # LC_CODE_SIGNATURE (including ad-hoc signatures)
            raise ValueError("IPA contains a signed Mach-O binary")
        if cmd == 0x32:  # LC_BUILD_VERSION
            if length < 24 or struct.unpack_from("<I", commands, offset + 8)[0] != 2:
                raise ValueError("IPA binary targets a platform other than iPhoneOS")
            device = True
        elif cmd == 0x25 and length >= 16:  # LC_VERSION_MIN_IPHONEOS in older device libraries
            device = True
        elif cmd in (0xC, 0x80000018) and length >= 24:  # LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB
            start = struct.unpack_from("<I", commands, offset + 8)[0]
            name = commands[offset + start:offset + length].split(b"\0", 1)[0]
            if name == b"/System/Library/Frameworks/Metal.framework/Metal":
                metal = True
        offset += length
    if offset != size or not device:
        raise ValueError("Missing iPhoneOS deployment target in Mach-O")
    if executable and not metal:
        raise ValueError("The device executable does not link Apple's Metal framework")


def inspect_ipa(path, version, build_number):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Duplicate IPA archive entry")
        for name in names:
            parts = PurePosixPath(name).parts
            if (name not in ("Payload/", APP) and not name.startswith(APP)) or ".." in parts:
                raise ValueError("IPA contains files outside the application bundle")
            if "_CodeSignature" in parts or name.endswith((".mobileprovision", "/CodeResources")):
                raise ValueError("IPA contains a signature or provisioning profile")
        plist = plistlib.loads(archive.read(APP + "Info.plist"))
        expected = {"CFBundlePackageType": "APPL", "CFBundleIdentifier": BUNDLE_ID,
                    "CFBundleShortVersionString": version, "CFBundleVersion": str(build_number),
                    "CFBundleExecutable": "wdfz", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                    "MinimumOSVersion": MINIMUM_OS, "UIRequiresFullScreen": True}
        for key, value in expected.items():
            if plist.get(key) != value:
                raise ValueError(f"Unexpected iOS property {key}: {plist.get(key)!r}")
        for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
            if set(plist.get(key, [])) != LANDSCAPE:
                raise ValueError("IPA must support both landscape orientations on iPhone and iPad")
        if set(plist.get("UIDeviceFamily", [])) != {1, 2} or not plist.get("NSLocalNetworkUsageDescription"):
            raise ValueError("IPA lacks iPhone/iPad support or its local network permission description")
        executable = archive.getinfo(APP + plist["CFBundleExecutable"])
        if not executable.external_attr >> 16 & stat.S_IXUSR:
            raise ValueError("IPA lost the executable permission")
        for item in archive.infolist():
            if item.is_dir():
                continue
            with archive.open(item) as stream:
                magic = stream.read(4)
                if item == executable or magic in MACH_MAGICS:
                    stream.seek(0)
                    inspect_macho(stream, item == executable)
        with archive.open(APP + "wdfz.pck") as pack:
            if pack.read(4) != b"GDPC":
                raise ValueError("IPA does not contain the Godot game pack")
        if archive.testzip() is not None:
            raise ValueError("Corrupt IPA archive")


def verify_packed_renderer(ipa, reports, probe_mac=False):
    """Check the shipped project settings using Godot's own PCK parser."""
    with tempfile.TemporaryDirectory(prefix="wdfz-ios-renderer-") as temp:
        directory = Path(temp)
        pack = directory / "wdfz.pck"
        with zipfile.ZipFile(ipa) as archive, archive.open(APP + pack.name) as src, pack.open("wb") as out:
            shutil.copyfileobj(src, out, length=1024 * 1024)
        args = ["--main-pack", str(pack), "--script", str(ROOT / "tools/ci/ios_renderer.gd")]
        output = run("packed-renderer", [ENGINE, "--headless", *args], reports, cwd=directory, timeout=60)
        if "IPA RENDERER SETTINGS: metal / mobile" not in output:
            raise ValueError("Could not confirm native Metal in the archived game pack")
        if not probe_mac:
            return False
        probe = run("metal-device", ["xcrun", "swift", "-e",
                    'import Metal; print(MTLCreateSystemDefaultDevice() == nil ? "absent" : "available")'],
                    reports, cwd=directory, timeout=120).strip().splitlines()
        if probe and probe[-1] == "absent":
            print("No Metal device on the macOS build host; verified archived renderer settings.", flush=True)
            return False
        if not probe or probe[-1] != "available":
            raise ValueError("Could not determine availability of a Metal device")
        output = run("metal-frame", [ENGINE, "--rendering-driver", "metal", "--rendering-method", "mobile",
                     "--windowed", "--resolution", "256x144", "--audio-driver", "Dummy", "--text-driver", "Dummy",
                     *args, "--", "--verify-metal-frame"], reports, cwd=directory, timeout=120)
        if "IPA METAL FRAME: passed" not in output:
            raise ValueError("The macOS host did not verify a native Metal frame")
        return True
