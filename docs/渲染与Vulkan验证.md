# 渲染与 Vulkan 验证

Android、Windows 和 Linux 使用 Vulkan，iOS 使用原生 Metal。渲染路径在 `project.godot` 固定；画面菜单支持独立模型／材质／粒子、渲染比例、阴影、抗锯齿、后期、帧率上限与垂直同步；五档预设仍作快捷入口，不切换图形 API。用法与兼容规则见[自定义画质与帧率](自定义画质与帧率.md)。

| 导出目标 | Godot 渲染器 | 驱动 |
| --- | --- | --- |
| Linux / Windows x86_64 | Forward+ | Vulkan |
| Android ARM64 | Mobile | Vulkan |
| iPhone／iPad ARM64 | Mobile | 原生 Metal |

iOS 导出将 `rendering_device/driver.ios` 设为 `metal`，使用 Godot Mobile，并关闭 iOS 的 Vulkan 回退。其他三个平台固定使用 Vulkan。所有平台均关闭 OpenGL 回退。

Android 继续要求 API 24+、ARM64。Android 版本达到要求不等于 GPU 满足 Vulkan 要求；官方模板根据 Mobile + Vulkan 自动写入必需的 `android.hardware.vulkan.version` 功能，以及 `org.godotengine.rendering.method=mobile` 元数据。导出脚本读取 APK 的实际 Manifest 验证这两项。横屏启动、强制全屏的启动参数、签名、16 KB 对齐和资源校验继续执行。

Android Debug 与 Release 都改用官方 Gradle 模板，自动安装到不入库的 `build/android-project/`。这是为了避开固定版本 Godot 4.6.3 非 Gradle 导出将 Vulkan `required`／`version` 写成字符串、导致 `aapt dump badging` 失败的问题。Gradle 使用 Android 工具链编译 Manifest，不修改引擎、不手工修补签名后的 APK，也不放宽校验。

## 材质与效果

场景材质、灯光、雾、天空、粒子、屏幕后处理与 UI 都经 Godot 的 Vulkan RenderingDevice 提交。现有 Godot shader 由引擎编译为 Vulkan 使用的着色器，不需要把游戏层改写成底层 Vulkan 调用。

`ScenePost` 保留旧版的颜色曲线、暗角和低 SAN 反馈；两次坐标变换用于复刻旧版屏幕坐标，不因更换后端随意翻转。落粉使用点图元与专用 spatial shader；异象、迷宫反色与死亡演出继续共用既有表现层。不能只看引擎启动成功，必须验证真实像素和场景。

## 五个预设的光影与渲染预算

2026-11-15 起改为按清晰度和有上限的光照预算分档，完整参数、旧配置迁移见[自定义画质与帧率](自定义画质与帧率.md)。五档是流畅／均衡／精细／高清／极清，默认 60 FPS；3D 像素上限依次为 480p／600p／720p／900p／1080p 的 16:9 等效面积，UI 保持原生清晰度。

所有档位都移除逐窗投影、普通灯具实时阴影、SSAO、泛光、体积雾和高倍抗锯齿。保留天空、普通雾、昼夜与停电、附近最多四盏局部灯，以及精细起的太阳和手电投影。最高只用 2× MSAA、2048 阴影图集；室内单张太阳阴影、室外最多两级。画质不改变规则、碰撞和存档。

Godot 4.6.3 Mobile 仍不启用 FSR 1 和 FXAA：前者不支持，后者曾在档案回放中复现编译停顿。工作线程池暂保留 8，背景见上游 [Godot #123060](https://github.com/godotengine/godot/issues/123060)。辉光现在已从全部渲染路径移除。更换引擎时仍需跑冷缓存和档案回放验证，不能仅凭效果减少就宣称引擎编译问题已修复。

## 空间剔除与性能对照

当前表现层对重复实例按空间与三角形预算分批，对复杂不透明大网格分块，并使用实际静态墙面做遮挡剔除；门和电梯不烘入遮挡数据。入口预览按需加载且限制缓存，普通调色仅在失焦时请求屏幕 mipmap。性能原因、权衡、实际测量和复测入口见[渲染性能分析与优化](渲染性能分析与优化.md)。Vulkan 后端与 Mobile 编译规避继续保留；画质预算已按上文调整。

## 开发验证

```bash
python tools/check.py                         # 规则、资源和生命周期；headless 不验证 GPU
python tools/check.py --mode windowed         # Vulkan Forward+ 全量回归
python tools/check.py --mode windowed --renderer mobile
xvfb-run -a python tools/ci/with_wayland.py python tools/export.py --platform linux
```

本机需要 Vulkan 驱动和显示服务。无 GPU 的 Linux CI 安装 `mesa-vulkan-drivers`、`libvulkan1`、`xvfb`、`weston`，共用 `setup-vulkan` action 显式选择 Lavapipe ICD，再通过 `xvfb-run -a` 运行上述窗口命令。它是真实 Vulkan API 上的软件渲染，不能用于宣称独显或手机的性能。

窗口回归要求 `get_current_rendering_driver_name()=="vulkan"`、对应渲染器与非空 RenderingDevice，日志必须含 `RENDERER VERIFIED`。颜色、落粉和遮挡用例会回读实际帧；headless 日志明确标记 dummy，不计入 Vulkan 验证。调试面板同时显示 API 与渲染器名称，便于排查设备。

截图也使用项目默认 Vulkan；可显式追加 `--rendering-method mobile` 检查移动渲染路径。例如：

```bash
godot --windowed --path . --rendering-driver vulkan --script res://tools/capture/capture_campus.gd
```

## 结果与发布边界

本次执行结果单独记录在[迁移一致性验证](迁移一致性验证.md)，早期 Compatibility / OpenGL 的记录保留原环境说明。Godot shaders 与原生 Vulkan 像素回归不替代 Android、Windows 真机帧率、耗电和长局稳定性验收。

公开 `v0.1.0` 在本次迁移前发布，保留原始二进制和签名；main 的 Vulkan 修改通过后续构建生效。不会用新后端的构建覆盖已经发布的同版本附件。


## 平台窗口与 Wayland

v0.2.0 起 Android 在项目启动配置、APK 启动参数与运行时设置三个入口强制全屏；旧 `full_screen=0` 设置不会关闭沉浸模式，主菜单、暂停与画面设置不提供全屏开关。Windows 与 Linux 的项目启动模式及新配置均为窗口模式，用户之后的全屏选择仍会保存。触屏模拟不会把桌面平台误判为 Android。

Linux 的 `display/display_server/driver.linuxbsd="wayland"` 使用引擎原生 Wayland 后端；连接失败由引擎回退 X11，`--display-driver x11` 可显式选择。两种窗口后端均使用 Vulkan，不改变渲染器。Linux 打包验证在独立 Weston 与 Xvfb 中分别测试正式可执行文件的默认窗口启动、显示驱动身份、正常退出，并加载导出的 PCK 验证全屏切换、校园帧及动态资源。Weston 运行在 Xvfb 父窗口中以提供虚拟鼠标设备，游戏本身直接连接 Wayland，不启动 XWayland；仅成功创建 Vulkan 设备而没有核对 Wayland 身份不能算通过。

`tools/check.py --mode windowed --display-driver wayland` 可在已有 Wayland 会话运行完整回归；默认窗口回归仍使用 X11。CI 的软件 Vulkan 结果是功能验证，不代表设备性能。

## 建模与室内日光

圆润无脸人形与平面窗户剪影保留。普通楼内外共享天空光、太阳、雾和曝光，夜间一起变暗；车库、异空间与停电保留特殊光照。2026-11-15 删除了贴在每扇假窗前的聚光投影，不再在进楼时扫描窗格三角形、生成额外灯光。模型和相邻视图统一为哑光漫反射，透明度、自发光、几何与碰撞不变。
