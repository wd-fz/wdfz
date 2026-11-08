"""由 assets/campus/layout/*.json 生成 content/worlds/campus/<场景>.tres，并把它们登记进 game/app/app.tscn 的 WorldRouter。

用法：python3 tools/export_scenes/gen_worlds.py（导出布局之后运行；结果可重复生成）。
落点取旧版 doEnterRoom 不带指定落点时的位置（export.js defaultSpawn）；noClock 的场景不推进日历。
"""
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAYOUT = ROOT / 'assets' / 'campus' / 'layout'
OUT = ROOT / 'content' / 'worlds' / 'campus'
APP = ROOT / 'game' / 'app' / 'app.tscn'


def world_ids():
    rooms = sorted(p.stem for p in LAYOUT.glob('*.json') if p.stem not in ('campus', 'out'))
    return ['out'] + rooms


def write_definition(i):
    if i == 'out':
        pos, yaw, calendar = (0.0, 0.05, 0.0), 0.0, True
    else:
        d = json.loads((LAYOUT / f'{i}.json').read_text())
        s = d['spawn']
        ang = s['ang'] if s['ang'] is not None else math.pi / 2
        pos = (s['scene_x'], 0.05, s['scene_z'])
        y = -ang - math.pi / 2
        yaw = math.degrees(math.atan2(math.sin(y), math.cos(y)))
        calendar = not d['flags'].get('noClock')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f'{i}.tres').write_text(f'''[gd_resource type="Resource" script_class="WorldDefinition" load_steps=3 format=3]

[ext_resource type="Script" path="res://game/presentation/world/world_definition.gd" id="1"]
[ext_resource type="PackedScene" path="res://game/presentation/world/campus/campus_world.tscn" id="2"]

[resource]
script = ExtResource("1")
world_id = &"{i}"
scene = ExtResource("2")
spawn_position = Vector3({pos[0]:.4f}, {pos[1]}, {pos[2]:.4f})
spawn_yaw_degrees = {yaw:.4f}
advances_calendar = {"true" if calendar else "false"}
properties = {{"scene_id": "{i}"}}
''')


def register(ids):
    s = APP.read_text()
    s = re.sub(r'\[ext_resource type="Resource" path="res://content/worlds/campus/[^"]+" id="campus_[^"]+"\]\n', '', s)
    lines = ''.join(f'[ext_resource type="Resource" path="res://content/worlds/campus/{i}.tres" id="campus_{i}"]\n' for i in ids)
    s = s.replace('\n[node name="GameApp"', lines + '\n[node name="GameApp"', 1)
    refs = ', '.join(['ExtResource("5")'] + [f'ExtResource("campus_{i}")' for i in ids])
    s = re.sub(r'worlds = Array\[ExtResource\("6"\)\]\(\[.*?\]\)', f'worlds = Array[ExtResource("6")]([{refs}])', s)
    s = re.sub(r'load_steps=\d+', f'load_steps={7 + len(ids)}', s, count=1)
    APP.write_text(s)


if __name__ == '__main__':
    ids = world_ids()
    for i in ids:
        write_definition(i)
    register(ids)
    print(f'{len(ids)} campus worlds registered')
