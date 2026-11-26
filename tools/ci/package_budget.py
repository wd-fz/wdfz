"""Require the export-time lossless optimizer in every automated package."""
import json

POLICY = {"version": 1, "model_tiers": [0, 1, 2, 3], "scene_block_max": 1048576, "lossless": True}


def clear_report(root, output):
    (root / "build/reports/package-size" / (output.name + ".json")).unlink(missing_ok=True)


def read_report(root, output):
    path = root / "build/reports/package-size" / (output.name + ".json")
    report = json.loads(path.read_text())
    if report.get("policy") != POLICY or report.get("lossless_verified", 0) != report.get("scenes") or report.get("scenes", 0) < 1:
        raise RuntimeError("The export did not verify lossless scene compaction")
    for kind in ("scene", "texture"):
        if not 0 < report.get(kind + "_bytes_after", 0) <= report.get(kind + "_bytes_before", 0):
            raise RuntimeError("The export has invalid resource size accounting")
    if not 0 < report.get("unique_textures", 0) <= report.get("textures", 0):
        raise RuntimeError("The export did not verify shared textures")
    if report.get("exterior_tiers") != POLICY["model_tiers"] or report.get("exterior_bytes", 0) <= 0:
        raise RuntimeError("The export is missing prepared resident exterior tiers")
    return {key: value for key, value in report.items() if key != "output"}


def verify_apk(archive):
    names = archive.namelist()
    if any(name.startswith(("assets/assets/campus_q4/", "assets/addons/")) for name in names):
        raise RuntimeError("APK includes retired models or editor plugins")
    if json.loads(archive.read("assets/assets/package_policy.json")) != POLICY:
        raise RuntimeError("APK is missing the current package policy")
    if not any(name.endswith(".glb.packed.scn") for name in names) or not any(name.startswith("assets/assets/packed_textures/") for name in names):
        raise RuntimeError("APK is missing compacted scenes or shared textures")
    for tier in POLICY["model_tiers"]:
        if f"assets/assets/campus/resident/out_{tier}.scn" not in names:
            raise RuntimeError(f"APK is missing prepared resident exterior tier {tier}")
