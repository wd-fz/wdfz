# 旧版建筑导出

以旧 Web 版的建筑和落点为基线。原生校园同时显示室内和室外，导出器在临时目录应用 `campus_geometry.patch`，将教室薄墙、教学楼外廊和天台，以及行政楼、实验楼、宿舍楼的楼梯开口做进模型。旧仓库工作树可以只读。

## 依赖

- Python 3.10+ 与 `pip install playwright`（使用环境里已有的 Chromium；也可设 `CHROMIUM_EXECUTABLE`）。
- 旧仓库检出：`git clone https://github.com/wd-fz/wd-fz.github.io`，检出参考基线 `0bf508a`。

## 用法

```bash
python3 tools/export_scenes/export_scenes.py --old <旧仓库目录>          # 全部场景：glb + 贴图 + 布局
python3 tools/export_scenes/export_scenes.py --old <旧仓库目录> --only out,teach1,teach2,teach3,teach4,teach5 --keep-scene-art
python3 tools/export_scenes/export_scenes.py --old <旧仓库目录> --layout-only
python3 tools/export_scenes/gen_worlds.py                                 # 生成 WorldDefinition 并登记进 app.tscn
```

只更新几何时，按可用模型档位分别设置 `--quality` 与对应的 `--out`。加上 `--keep-scene-art` 可复用已有中文标牌等贴图。教室隔墙深 0.20 米，门扇的开关位置与碰撞从同一套门轴尺寸导出。

## 过程

1. 本地起一个静态服务器打开旧版首页，等 `Engine.ready()` 与当前画质的模型包读好（默认第 2 档）。
2. 注入 `vendor/gltf-exporter.js`（three.js r187 的 GLTFExporter 与 BufferGeometryUtils，按全局 `THREE` 打包，MIT 许可见 `vendor/THREE-LICENSE.txt`）和 `export.js`。
3. `export.js` 调用旧版 `buildRoomGeometry` / `buildOutdoorGeometry`：
   - 量化顶点属性还原为浮点（Godot 不支持 `KHR_mesh_quantization`）；
   - 实例化网格保留原型 + 实例变换／颜色（extras），其余网格按材质烘焙合并；
   - Phong / Lambert 材质按颜色、贴图、自发光、透明换成 glTF 标准材质；
   - 普通房门按旧版 `OPENDOORS` 分别建关、开两份门扇；
   - 布局与碰撞取旧版 `SpaceLayout`、`FURN_SOLID`、`roofSolids`、`OUT_SOLID`、`BOUND`、`DOOR_LOCKS`、`CAMPUS_DOOR`、`entryNear`、`leaveSeat` 的结果，不重新推导。
4. Python 把 glb 内嵌贴图按哈希拆到 `assets/campus/textures/`，写出 glb 与 JSON。

## 已知限制

- 材质是近似转换：旧版 `onBeforeCompile` 着色、阴影、雾、后期、灯光不在 glb 里，由 Godot 表现层另行移植。
- 楼梯井（`stair_*`）的坡面碰撞、钟楼旋梯、电梯门、虚空迷宫按高度的碰撞是旧版的动态规则，未导出成碰撞盒；对应系统移植时再接。
