# 武大附中 · 里世界 — Godot 移植版

后续开发在本仓库进行。[旧 Web 版仓库](https://github.com/wd-fz/wd-fz.github.io)已停止维护，仅作为移植参考。

**当前交付：移植框架 + 正式校园建筑。** 旧版全部 42 个室内场景和室外校园已由旧版自己的建模函数导出进 Godot（建筑不变），碰撞取旧版自己的碰撞数据；新局从教学楼一楼本人座位旁开始，可以开关房门、穿过连续校园的 10 道门进出楼、按 E 进地下车库和走出出口。课表与时间规则、SAN／违规、背包、楼梯与电梯、巡察者、异象、剧情、音效、灯光与结局尚待迁移，进度见[计划目录](docs/plan/README.md)。

![教学楼一楼开局位置](pictures/正式校园建筑/01-教学楼1F-开局起身位置.jpg)

## 运行

1. 安装 **Godot 4.6.3 标准版**，不需要 .NET。引擎版本固定在 [.godot-version](.godot-version)。
2. 克隆本仓库，在 Godot 项目管理器导入根目录的 [project.godot](project.godot)。
3. 等待首次资源导入，按 **F6** 运行 `scenes/app.tscn`，或直接按 **F5** 运行项目。
4. 点「进入测试场景」（现在进入正式校园的教学楼一楼），朝门走按 **E** 开门；从一楼走廊南端的正门直接走出去就到室外；按 **Esc** 打开暂停页，验证保存、读取和返回菜单。框架示例房间仍保留为 `migration_lab`，测试用。

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
| 参考完整的小模块 | [告示牌示例](features/demo/demo_module.gd)与[功能目录说明](features/README.md) |
| 运行检查或提交修改 | [贡献指南](CONTRIBUTING.md) |
| 导入外部资源 | [资源约定](assets/README.md) |
| 重新导出旧版建筑 | [旧版建筑导出](tools/export_scenes/README.md)与[正式校园资源](assets/campus/README.md) |

项目没有全局游戏状态 Autoload。`GameApp` 是组合入口，每局新建 `GameSession`；规则对象不读场景树或文件，场景与 UI 通过信号接入。新增功能有独立模块 ID、交互 ID、状态版本与保存域。

## 验证

安装 Python 3.10+，确保 `godot` 在 PATH 中：

```bash
python tools/check.py
```

若引擎不在 PATH，设置 `GODOT_BIN` 为 Godot 可执行文件的路径。检查会核对版本、规则层边界、执行真实 Godot 导入和无窗口回归；脚本报错即使 Godot 返回 0，也判为失败。有显示环境时加 `--windowed` 同时检查窗口输入。GitHub Actions 使用 Xvfb 运行两种模式。

有显示环境时可生成实际渲染预览：

```bash
godot --path . --script res://tools/capture_preview.gd
```

图片输出到 `build/previews/`，不会覆盖正式存档。正式校园的预览用 `--script res://tools/capture_campus.gd`。当前自动验证与限制见[框架验证记录](docs/框架验证记录.md)与[正式校园验证记录](docs/正式校园验证记录.md)。

## 存档与范围

本机测试存档为 `user://saves/slot_1.json`，应用数据目录名为 `wdfz-godot`。保存先写临时文件，保留前一份 `.bak` 后替换；读取先完成格式、场景 ID 和模块状态校验，再替换会话。未启用模块的 JSON 数据会保留。

这是独立的 `wdfz-godot` 格式 v1，**不能直接读取 Web 版存档**。示例时钟采用完整自然日 20 分钟的四段预算，但尚未移植正式开局时刻、剧情慢速窗口、课表、跨日压力和相关事件，不能拿演示场景判断游戏平衡。

许可证沿用仓库已有的 [GNU AGPL v3](LICENSE)。`assets/campus/` 的模型与贴图由旧版本项目自有的建模与贴图脚本生成，来源记录见[正式校园资源](assets/campus/README.md)；旧版音频尚未搬入。
