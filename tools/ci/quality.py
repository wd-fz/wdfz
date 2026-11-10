"""Dependency-free repository checks; Godot remains the GDScript parser."""
from pathlib import Path
import configparser
import re


def code_only(text):
    return re.sub(r'"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27|#[^\n]*',
                  lambda m: "\n" * m.group().count("\n"), text)


def rule_errors(path, text, classes):
    code = code_only(text)
    errors = []
    forbidden = re.compile(
        r'\b(?:Input|FileAccess|DirAccess|RenderingServer|DisplayServer|ResourceLoader|ResourceSaver)\b'
        r'|\b(?:get_tree|get_node|load|preload)\s*\('
        r'|\bextends\s+(?:Node\w*|Control|Resource|CanvasLayer|SceneTree|CharacterBody\w*)\b')
    allowed = ("game/core/",) if path.startswith("game/core/") else ("game/core/", "game/features/")
    for number, line in enumerate(code.splitlines(), 1):
        if forbidden.search(line):
            errors.append(f"{path}:{number}: rule code depends on an engine adapter")
        for word in set(re.findall(r'\b[A-Za-z_]\w*\b', line)):
            target = classes.get(word, "")
            if target and not target.startswith(allowed):
                errors.append(f"{path}:{number}: rule code depends on {word} ({target})")
    return errors


def rendering_errors(text):
    config = configparser.ConfigParser(interpolation=None)
    try:
        config.read_string("[godot]\n" + text)
    except configparser.Error as error:
        return [f"project.godot: cannot validate rendering settings: {error}"]
    rendering = config["rendering"] if config.has_section("rendering") else {}
    expected = {"renderer/rendering_method": '"forward_plus"',
                "renderer/rendering_method.mobile": '"mobile"',
                "rendering_device/driver": '"vulkan"',
                **{f"rendering_device/driver.{platform}": '"vulkan"' for platform in ("linuxbsd", "windows", "android")},
                "rendering_device/fallback_to_d3d12": "false", "rendering_device/fallback_to_opengl3": "false"}
    errors = [f"project.godot: {key} must be {value}" for key, value in expected.items() if rendering.get(key) != value]
    for key, value in rendering.items():
        if key.startswith("rendering_device/driver") and value != '"vulkan"':
            errors.append(f"project.godot: {key} selects a non-Vulkan driver")
        if key.startswith("renderer/rendering_method") and value not in ('"forward_plus"', '"mobile"'):
            errors.append(f"project.godot: {key} selects a non-Vulkan renderer")
    return errors


def check(root: Path):
    scripts = sorted((root / "game").rglob("*.gd"))
    errors, classes, uids = rendering_errors((root / "project.godot").read_text(encoding="utf-8")), {}, {}
    for old in ("app", "actors", "core", "features", "scenes", "ui", "world"):
        if (root / old).exists():
            errors.append(f"Runtime files belong under game/, found old root {old}/")
    for path in scripts:
        name = re.search(r'^class_name\s+(\w+)', path.read_text(encoding="utf-8"), re.M)
        if name:
            if name[1] in classes:
                errors.append(f"Duplicate class {name[1]}: {path}")
            classes[name[1]] = path.relative_to(root).as_posix()
    for base in ("game", "tests", "tools/capture", "tools/benchmarks"):
        for path in sorted((root / base).rglob("*.gd")):
            uid_file = path.with_suffix(".gd.uid")
            if not uid_file.exists():
                errors.append(f"Missing UID: {uid_file.relative_to(root)} (import in Godot, then commit it)")
                continue
            uid = uid_file.read_text().strip()
            if not re.fullmatch(r"uid://[a-z0-9]+", uid) or uid in uids:
                errors.append(f"Invalid or duplicate UID: {uid_file.relative_to(root)}")
            uids[uid] = path
    rules = 0
    for path in scripts:
        relative = path.relative_to(root).as_posix()
        if relative.startswith(("game/core/", "game/features/")):
            rules += 1
            errors.extend(rule_errors(relative, path.read_text(encoding="utf-8"), classes))
    resources = [root / "project.godot"]
    for base in ("game", "content"):
        resources += [p for p in (root / base).rglob("*") if p.suffix in (".gd", ".tscn", ".tres")]
    for path in resources:
        for ref in re.findall(r'["\x27]res://([^"\x27\n]+)["\x27]', path.read_text(encoding="utf-8")):
            if not ref.startswith(("game/", "content/", "assets/")):
                errors.append(f"{path.relative_to(root)}: runtime references a development path: {ref}")
            elif "%" not in ref and Path(ref).suffix and not (root / ref).exists():
                errors.append(f"{path.relative_to(root)}: missing resource {ref}")
    for base in ("docs", "pictures"):
        if not (root / base / ".gdignore").exists():
            errors.append(f"{base}/ needs .gdignore to keep evidence out of Godot imports")
    if not scripts or not rules:
        errors.append("No runtime/rule scripts found; refusing a vacuous check")
    if errors:
        raise ValueError("\n".join(errors))
    return f"Structure check: {len(scripts)} runtime scripts, {rules} rule scripts, {len(uids)} unique UIDs."
