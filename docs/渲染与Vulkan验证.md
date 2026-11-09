# 渲染与 Vulkan 验证

当前 main 的原生渲染统一使用 Vulkan。渲染路径在 `project.godot` 固定；画质菜单继续控制五档模型、渲染比例、阴影、MSAA 和粒子数量，不切换图形 API。

| 导出目标 | Godot 渲染器 | 驱动 |
| --- | --- | --- |
| Linux / Windows x86_64 | Forward+ | Vulkan |
| Android ARM64 | Mobile | Vulkan |

`rendering_device/driver` 及三个导出目标的覆盖值均为 `vulkan`；关闭 `fallback_to_opengl3` 与 `fallback_to_d3d12`。设备或驱动不满足 Godot 的 Vulkan 要求时应报告初始化失败，不静默运行另一套后端。当前不导出 Web、macOS 或 iOS。

Android 继续要求 API 24+、ARM64。Android 版本达到要求不等于 GPU 满足 Vulkan 要求；官方模板根据 Mobile + Vulkan 自动写入必需的 `android.hardware.vulkan.version` 功能，以及 `org.godotengine.rendering.method=mobile` 元数据。导出脚本读取 APK 的实际 Manifest 验证这两项。横屏启动、强制全屏的启动参数、签名、16 KB 对齐和资源校验继续执行。

Android Debug 与 Release 都改用官方 Gradle 模板，自动安装到不入库的 `build/android-project/`。这是为了避开固定版本 Godot 4.6.3 非 Gradle 导出将 Vulkan `required`／`version` 写成字符串、导致 `aapt dump badging` 失败的问题。Gradle 使用 Android 工具链编译 Manifest，不修改引擎、不手工修补签名后的 APK，也不放宽校验。

## 材质与效果

场景材质、灯光、雾、天空、粒子、屏幕后处理与 UI 都经 Godot 的 Vulkan RenderingDevice 提交。现有 Godot shader 由引擎编译为 Vulkan 使用的着色器，不需要把游戏层改写成底层 Vulkan 调用。

`ScenePost` 保留旧版的颜色曲线、暗角和低 SAN 反馈；两次坐标变换用于复刻旧版屏幕坐标，不因更换后端随意翻转。落粉使用点图元与专用 spatial shader；异象、迷宫反色与死亡演出继续共用既有表现层。不能只看引擎启动成功，必须验证真实像素和场景。

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
