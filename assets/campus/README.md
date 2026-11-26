# 正式校园资源（由旧 Web 版导出）

本目录的场景和布局由 [`tools/export_scenes/`](../../tools/export_scenes/README.md) 在旧 Web 版基线上生成。修改建筑位置时，在导出源中编辑布局并重新生成模型和碰撞。

| 目录 | 内容 |
| --- | --- |
| `scenes/<场景>.glb` | 42 个室内场景与室外校园 `out`。几何来自旧版 `buildRoomGeometry` / `buildOutdoorGeometry`，按材质合并；实例化网格保留一份原型，实例变换与颜色写在节点 `extras`（`wdfz_instances`、`wdfz_colors`），运行时由 `CampusWorld` 还原为 MultiMesh。普通房门每扇各有 `door_closed__c_r`、`door_open__c_r` 两个节点。 |
| `textures/` | 按内容哈希去重的贴图，glb 以相对路径引用 |
| `layout/<场景>.json` | 格子、墙体、家具碰撞、门洞、楼梯、默认落点和开局座位。室外布局也提供道路、建筑占地与边界，游戏地图直接读取同一份布局。 |
| `layout/campus.json` | 连续校园出入口表、门锁表、单位常量（`U2M = 1/9`、`TTILE = 9`、`PRAD = 3`、视高 1.65 m）、开局房间 |

## 来源与授权

- 参考基线：`wd-fz/wd-fz.github.io@0bf508a47eac154c2a7047cdb45d314f61c48fdc`（Web 版最后的 main）。
- 模型来自旧仓库 `tools/blender/` 的建模脚本打包结果（`game3d/assets/models_l*.js`）和旧版 `game3d/js/model/`、`content/` 的程序化建模；贴图来自旧仓库 `tools/textures/build_textures.py` 的离线生成结果（`textures_*.js`）。均为本项目自有内容，随本仓库的 AGPL v3 发布。
- 黑板、门牌、车牌等文字贴图是旧版在浏览器 Canvas 上现场绘制的，导出时由无头 Chromium 光栅化，所用字体为导出环境的系统字体（Noto CJK）。正式发行前与字体打包一起复核。
- 导出画质：旧版第 2 档「精细」（512 贴图、标准分段）。草地是画质相关的表现层装饰，未导出。

## 实景校园建筑与陈设

`architecture/` 收录楼体装饰、两种连廊、球场、地理园和室内家具。按游戏地图方位，教学楼教室门朝北，外廊面向绿色广场，一楼入口紧邻西侧楼梯塔。透过入口两侧的红砖柱可以看进走廊，内墙边设一排座椅。柱距和走道宽度按游戏格网估算。「橙色之路」从教学楼北侧外廊东端接往实验楼二楼。实验楼西侧拱门接地理园一侧的步道，行政楼北门通往运动区。宿舍两翼从西侧入口进入，内侧阳台和食堂西门朝向院子。室内尺寸沿用游戏地图。模型、碰撞和通行点使用 `tools/export_scenes/campus_placement.json` 的门洞配置。[720 云·绿色广场视点](https://www.720yuntu.com/tour/7e11b56b6f8381ab?startscene=scene_2612736d453a9c83)

在仓库根目录运行 `python3 tools/remodel/campus_architecture.py` 可以重新生成模型、材质贴图和庭院碰撞。生成工具使用 NumPy 和 Pillow。Godot 通过 `CampusArchitecture` 把这些资源装入可玩场景及相邻场景预览。

`assets/ui/campus_satellite.jpg` 由本项目的室外校园模型生成，沿用项目的 AGPL v3。正交相机北朝上，画幅与 `campus.json` 中的 `bound_map` 对齐。修改室外布局后，从仓库根目录运行 `godot --windowed --rendering-driver vulkan --audio-driver Dummy --script res://tools/capture/capture_campus_satellite.gd` 重新烘焙底图。

## 坐标

1 Godot 单位 = 1 米，+Y 向上，与旧版 three.js 场景坐标一致。室内场景以房间中心为原点（旧版 `worldToScene`），室外以旧版世界原点为原点；换算见 `game/features/campus/campus_geometry.gd`。
