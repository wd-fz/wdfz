# 武大附中 · 里世界 — Godot 移植版

后续开发在本仓库进行。[旧 Web 版仓库](https://github.com/wd-fz/wd-fz.github.io)已停止维护，仅作为移植参考。

**当前已具备正式校园与主要公开玩法。** 42 个室内场景、室外校园、楼梯／连廊／电梯、校园日程、背包与调查、巡察与异象、公开结局路线均已接入；声音、演出与设置也已有移植实现。不同系统的验收范围和剩余缺口见[计划目录](docs/plan/README.md)，不能把开发验证包视为完整发行验收。

运行时代码集中在 `game/`，资源在 `assets/` 和 `content/`；测试、开发工具与文档独立。目录职责、CI 与构建下载见[项目结构与持续集成](docs/项目结构与持续集成.md)。

![教学楼一楼开局位置](pictures/正式校园建筑/01-教学楼1F-开局起身位置.jpg)

## 运行

1. 安装 **Godot 4.6.3 标准版**，不需要 .NET。引擎版本固定在 [.godot-version](.godot-version)。
2. 克隆本仓库，在 Godot 项目管理器导入根目录的 [project.godot](project.godot)。
3. 等待首次资源导入，按 **F5** 运行项目；也可打开 `game/app/app.tscn` 后按 **F6** 运行。
4. 点「预知梦 · 新游戏」并选择天赋；开场结束或跳过后，坐在教学楼一楼的座位上，移动即起身；朝门按 **E** 开门，走廊南端正门直接走出去就到室外；走廊两端的楼梯口直接走进去上下楼；电梯门口按 **E** 呼梯，轿厢里按 **E** 选层、**V** 关门；**Tab** 背包、**1/2** 快捷栏、**F** 手电；按 **Esc** 打开暂停页，验证保存、读取和返回菜单。框架示例房间仍保留为 `migration_lab`，测试用。

也可通过命令行运行：

```bash
godot --editor --path .
godot --path .
```

键鼠：WASD／方向键移动、鼠标环视、Shift 奔跑、E 交互、Esc 暂停；失去鼠标捕获后点击场景重新捕获。触屏：左侧摇杆移动、右侧上方滑动环视、右下角交互与奔跑；主菜单可以手动启用控件。切出应用会暂停，切回来后主动继续。

默认使用 **Compatibility / OpenGL**，便于普通设备打开框架。渲染器属于表现层，可以在 Godot 项目设置中切换；当前没有做 Vulkan、移动设备或不同渲染器的性能与效果承诺。

界面使用系统字体回退，Linux 无中文字体时安装 Noto Sans CJK；正式发行前再确定可再分发的字体与资源包。本框架没有联网、账号或在线资源依赖。

## 给接手者的入口

| 要做什么 | 从哪里开始 |
| --- | --- |
| 了解分层和状态归属 | [架构与模块接口](docs/架构与模块接口.md) |
| 迁移一个玩法、房间或模型 | [移植接入指南](docs/移植接入指南.md) |
| 选择下一项工作 | [计划目录](docs/plan/README.md) |
| 参考完整的小模块 | [告示牌示例](game/features/demo/demo_module.gd)与[功能目录说明](game/features/README.md) |
| 运行检查或提交修改 | [贡献指南](CONTRIBUTING.md) |
| 导入外部资源 | [资源约定](assets/README.md) |
| 重新导出旧版建筑 | [旧版建筑导出](tools/export_scenes/README.md)与[正式校园资源](assets/campus/README.md) |

项目没有全局游戏状态 Autoload。`GameApp` 是组合入口，每局新建 `GameSession`；规则对象不读场景树或文件，场景与 UI 通过信号接入。新增功能有独立模块 ID、交互 ID、状态版本与保存域。

## 验证

安装 Python 3.10+，确保 `godot` 在 PATH 中：

```bash
python tools/check.py
```

若引擎不在 PATH，设置 `GODOT_BIN` 为 Godot 可执行文件的路径。检查会核对版本、规则层边界、执行真实 Godot 导入和无窗口回归；脚本报错即使 Godot 返回 0，也判为失败。有显示环境时加 `--windowed` 同时检查窗口输入。GitHub Actions 分别执行结构检查、无窗口回归、Xvfb 窗口回归，并在通过后导出桌面验证包。日志和结果均作为 Artifacts 保存。

有显示环境时可生成实际渲染预览：

```bash
godot --path . --script res://tools/capture/capture_preview.gd
```

图片输出到 `build/previews/`，不会覆盖正式存档。正式校园的预览用 `--script res://tools/capture/capture_campus.gd`。当前自动验证与限制见[框架验证记录](docs/框架验证记录.md)与[正式校园验证记录](docs/正式校园验证记录.md)。

## 开发验证包

到 [Actions → Godot CI](https://github.com/wd-fz/wdfz/actions/workflows/godot.yml) 的成功运行中下载 `desktop-builds-<提交 SHA>`。Linux 与 Windows 各有一个 ZIP，完整解压后运行。Linux 包有启动和包内资源检查；Windows 当前仅验证导出，真实设备验收仍待完成。

本地导出：安装同版本桌面 export templates 后运行 `python tools/export.py`。详细安装、日志与限制见[项目结构与持续集成](docs/项目结构与持续集成.md)。

## 存档与范围

本机测试存档为 `user://saves/slot_1.json`，应用数据目录名为 `wdfz-godot`。保存先写临时文件，保留前一份 `.bak` 后替换；读取先完成格式、场景 ID 和模块状态校验，再替换会话。未启用模块的 JSON 数据会保留。

Godot 使用独立的 `wdfz-godot` 存档格式。专用旧档导入只迁移玩家自身状态，异象、剧情与路线进度重新开始。正式校园有首日 11:40 开局、课表、跨日压力与特殊时间窗口；框架示例房间的时钟仅供协议测试。

许可证沿用仓库已有的 [GNU AGPL v3](LICENSE)。`assets/campus/` 的模型与贴图由旧版本项目自有的建模与贴图脚本生成，来源记录见[正式校园资源](assets/campus/README.md)；音频由旧版公开配方烘焙，生成入口在 `tools/audio_bake/`。
