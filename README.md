# 武大附中 · 里世界 — Godot 移植版

后续开发在本仓库进行。[旧 Web 版仓库](https://github.com/wd-fz/wd-fz.github.io)已停止维护，仅作为移植参考。

**正式版：** [v0.3.0 下载与说明](https://github.com/wd-fz/wdfz/releases/tag/v0.3.0)，提供 Android ARM64、Windows x86_64 与 Linux x86_64。三个平台统一使用 Vulkan；Android 正式签名，可覆盖升级 v0.1.0／v0.2.x，独立于 Debug 包安装。

**Android 启动即横屏并强制全屏；Windows / Linux 默认窗口化；竖屏不受维护。** 桌面与移动端都以横屏游玩为目标，优先适配常见横屏比例下的视野、界面和触屏操作。竖屏不作为后续迁移、回归或发布验收目标；早期竖屏截图与验证记录仅保留为历史证据。

**当前已具备正式校园与主要公开玩法。** 42 个室内场景、室外校园、楼梯／连廊／电梯、校园日程、背包与调查、巡察与异象、公开结局路线均已接入；声音、演出与设置也已有移植实现。不同系统的验收范围和剩余缺口见[计划目录](docs/plan/README.md)，不能把开发验证包视为完整发行验收。

运行时代码集中在 `game/`，资源在 `assets/` 和 `content/`；测试、开发工具与文档独立。目录职责、CI 与构建下载见[项目结构与持续集成](docs/项目结构与持续集成.md)。

**合作联机：** v0.3.0 新增局域网合作与「远程合作 · Terracotta」，支持 2–4 人好友合作。远程房主分享邀请码，好友异地加入，无需自行租服务器；Android 首次连接需允许系统 VPN 请求。开发环境需先获取固定版本组件，具体步骤、网络限制与验证范围见[远程合作](docs/远程合作.md)。v0.2.x 发行包不含合作模式，所有成员均需更新到相同构建。

![教学楼一楼开局位置](pictures/正式校园建筑/01-教学楼1F-开局起身位置.jpg)

## 运行

1. 安装 **Godot 4.6.3 标准版**，不需要 .NET。引擎版本固定在 [.godot-version](.godot-version)。
2. 克隆本仓库，在 Godot 项目管理器导入根目录的 [project.godot](project.godot)。
3. 等待首次资源导入，按 **F5** 运行项目；也可打开 `game/app/app.tscn` 后按 **F6** 运行。
4. 点「预知梦 · 新游戏」并选择天赋；开场结束或跳过后，坐在教学楼一楼的座位上，移动即起身；朝门按 **E** 开门，走廊南端正门直接走出去就到室外；走廊两端的楼梯口直接走进去上下楼；电梯门口按 **E** 呼梯，轿厢里按 **E** 选层、**V** 关门；**Tab** 背包（左边格子、右边说明与操作）、**1/2** 快捷栏、**F** 手电；背包里丢弃的东西会留在脚边的地上，低头看着它按 **E** 捡回；按 **Esc** 打开暂停页，验证保存、读取和返回菜单。框架示例房间仍保留为 `migration_lab`，测试用。

手机横屏：摇杆只控制移动，点按「奔跑：关／开」切换走跑，可同时拖动视角与点按动作按钮；体力不足或伤势限制时会显示「暂不能跑」。坐在座位上时，交互提示固定为「站起来」，移动也可起身。启动时先播放一段开机动画（任意键／点击可跳过），随后菜单背后的校园以一段「睁眼」动画进入，固定在左侧的侧边主菜单同时自动展开，单人入口为「继续入梦／新的轮回／画廊与遗物／感官设置／逃离现实」，合作入口为「局域网合作／远程合作 · Terracotta」；背景默认是一张缓慢转动的校园全景图（傍晚浓雾里教学楼与实验楼之间的广场，预先渲染的图片，不实时渲染），可在「设置 → 画面 → 主菜单实景环绕」关闭，改为静态夜景图；开启「减少闪烁」时直接显示静态展开的菜单。选好天赋或「继续入梦」后会先显示加载画面，校园模型在后台读取与处理，完成后进入开场。暂停页及各面板采用统一界面；继续、保存与返回等主要入口保持清晰。设置按画面、声音、操作、舒适、数据分类，更改即时生效并自动保存。Android 的启动 Activity 声明横屏，设置中的「横屏自动旋转」只决定能否左右翻转。Android 始终全屏，主菜单、暂停和设置均隐藏全屏开关，旧的窗口偏好不再生效。桌面新配置默认窗口化，保留已保存的显示模式，可用 `--windowed` / `--fullscreen` 指定启动模式。Linux 首选原生 Wayland，不依赖 XWayland；连接失败时回退到 X11，也可用 `--display-driver x11` 显式指定。

也可通过命令行运行：

```bash
godot --editor --path .
godot --path .
```

键鼠：WASD／方向键移动、鼠标环视、Shift 奔跑、E 交互、Esc 暂停；除暂停固定为 Esc 外，键盘按键都可在「设置 → 键位」改成两个自选键位。失去鼠标捕获后点击场景重新捕获。触屏：左侧摇杆移动、右侧上方滑动环视、右下角交互与奔跑；「设置 → 操作 → 调整触屏布局」可逐个拖动、缩放每个控件并调整透明度。主菜单可以手动启用控件。单人切出应用会暂停，切回来后主动继续；联机只停本人的输入，房主仍继续服务。

v0.2.0 起统一使用 **Vulkan**：Linux／Windows 使用 **Forward+**，Android 使用 **Mobile**；关闭 OpenGL 与 D3D12 自动回退。需要支持相应 Godot Vulkan 渲染路径的设备和驱动，Android 7.0+ 本身不保证显卡支持。五档预设可快速填入参数，也可独立调整分辨率、模型／材质／粒子、阴影、后期与抗锯齿。支持 20–360 FPS 或不限帧率、独立垂直同步；详见[自定义画质与帧率](docs/自定义画质与帧率.md)。配置、验证命令与设备要求见[渲染与 Vulkan 验证](docs/渲染与Vulkan验证.md)。已发布的 v0.1.0 是迁移前的版本，其附件不随 main 更新。

界面使用系统字体回退；Linux 无中文字体时安装 Noto Sans CJK，Android 使用系统中文字体。单人无需网络、账号或在线资源。局域网合作使用设备之间的 ENet 连接，不依赖云服务器。

main 已将[生成插画](assets/ui/illustrations/README.md)接入物品、天赋、手机、64 项成就、死亡与结局档案、9 档评级、调查笔记、地图地标、菜单与设置等界面。封存条目不提前展示剧情图片；地图继续使用实际空间和探索记录。游戏内实拍见[物品、天赋与手机](pictures/物品天赋与手机插画/)及[界面与档案插画](pictures/界面与档案插画/)。

## 局域网合作

主菜单「新的轮回 → 局域网合作」支持 2–4 人建房／加入、分头探索、物品交付、合作存档、原成员重连和六条公开结局。个人菜单不暂停世界；全队暂停由房主发起。隐藏内容与 DLC 暂保留为单人入口。

具体连接步骤与限制见[局域网合作](docs/局域网合作.md)，工程入口和实测边界见[局域网联机验证](docs/局域网联机验证.md)。目前源码中的合作功能仍需三平台真实设备与自然四人完整游玩验收，不代表已发布的 v0.3.0 包具有联机功能。

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

若引擎不在 PATH，设置 `GODOT_BIN` 为 Godot 可执行文件的路径。检查会核对版本、规则层边界、执行真实 Godot 导入和无窗口回归；脚本报错即使 Godot 返回 0，也判为失败。有 Vulkan 显示环境时加 `--windowed` 同时检查窗口输入；加 `--renderer mobile` 可验证 Android 使用的渲染路径。GitHub Actions 分别执行结构检查、无窗口回归、Vulkan Forward+ 与 Mobile 窗口回归，并在通过后导出桌面验证包。日志和结果均作为 Artifacts 保存。

有显示环境时可生成实际渲染预览：

```bash
godot --windowed --path . --script res://tools/capture/capture_preview.gd
```

图片输出到 `build/previews/`，不会覆盖正式存档。正式校园的预览用 `--script res://tools/capture/capture_campus.gd`。当前自动验证与限制见[框架验证记录](docs/框架验证记录.md)与[正式校园验证记录](docs/正式校园验证记录.md)。

## 开发验证包

到 [Actions → Godot CI](https://github.com/wd-fz/wdfz/actions/workflows/godot.yml) 的成功运行中下载 `desktop-builds-<提交 SHA>`。Linux 与 Windows 各有一个 ZIP，完整解压后运行。Linux 包有启动和包内资源检查；Windows 当前仅验证导出，真实设备验收仍待完成。

本地导出：安装同版本桌面 export templates、Xvfb 和 Weston 后运行 `xvfb-run -a python tools/ci/with_wayland.py python tools/export.py`。详细安装、日志与限制见[项目结构与持续集成](docs/项目结构与持续集成.md)。

Android 调试包在 [Actions → Android Debug](https://github.com/wd-fz/wdfz/actions/workflows/android-debug.yml) 的成功运行中下载 `wdfz-android-debug-arm64-<SHA>`。解压后安装其中的 APK，支持 ARM64、Android 7.0 及以上且具备 Vulkan 的设备；采用独立调试包名，横屏运行并自动启用触屏控件。构建检查签名、Debug 标记、启动横屏与 Vulkan 必需功能声明、Mobile 渲染器元数据、16 KB 对齐和运行时资源，尚未代表 Android 真机运行验收。本地 Linux 构建入口为 `python tools/export_android.py --sdk <Android SDK 路径>`。

## 存档与范围

本机测试存档为 `user://saves/slot_1.json`，应用数据目录名为 `wdfz-godot`。保存先写临时文件，保留前一份 `.bak` 后替换；读取先完成格式、场景 ID 和模块状态校验，再替换会话。未启用模块的 JSON 数据会保留。

Godot 使用独立的 `wdfz-godot` 存档格式。专用旧档导入在独立候选会话中转换并校验玩家状态、路线、巡察、异象、检查、图纸与相册，保留原始数据；未完成迁移的模块仍见[迁移差异](docs/plan/与旧版差异与迁移.md)，不能视作所有旧档无损兼容。正式校园有首日 11:40 开局、课表、跨日压力与特殊时间窗口；框架示例房间的时钟仅供协议测试。

许可证沿用仓库已有的 [GNU AGPL v3](LICENSE)。`assets/campus/` 的模型与贴图由旧版本项目自有的建模与贴图脚本生成，来源记录见[正式校园资源](assets/campus/README.md)；音频由旧版公开配方烘焙，生成入口在 `tools/audio_bake/`。
