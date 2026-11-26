# 开发工具

| 入口 | 用途 |
| --- | --- |
| `python tools/export_reference.py --source <旧版目录> --chromium <浏览器路径>` | 从真实 Web 运行时生成碰撞、课表、镜头和画质对照样本；正常 CI 直接读取已提交样本 |
| `python tools/check.py` | 结构、依赖边界、真实 Godot 导入与回归 |
| `python tools/export.py` | Linux／Windows 开发包与 Linux Vulkan 启动／包内容检查（需显示服务） |
| `python tools/export_android.py` | Linux 上生成并验证签名 Android Debug APK（ARM64） |
| `python tools/export_ios.py` | 在 macOS 上用 Xcode 构建并验证未签名的 iPhone／iPad ARM64 IPA，先用 `python tools/ci/install_godot.py --ios` 安装匹配的编辑器与模板 |
| [导出体积优化插件](../addons/package_optimizer/plugin.gd) | 导出时无损重排场景压缩块、共享相同纹理；自动生成体积与校验报告 |
| `python tools/ci/install_godot.py --templates` | Linux 上安装固定版本官方引擎和两个桌面 release 模板 |
| `python tools/ci/install_godot.py --android-debug` | 安装同版本 Android Gradle 模板与预编译引擎库 |
| `godot --windowed --path . --script res://tools/capture/capture_campus.gd` | 实际渲染校园截图，需要显示服务 |
| `python tools/benchmarks/campus_load.py --renderer mobile --quality 2 --samples 3` | 在 Linux 上分别启动新进程，测量新开局、读取该局存档和从教学楼穿门到室外。 |
| [export_scenes](export_scenes/README.md) | 从旧 Web 版导出建筑、贴图、布局与世界登记 |
| [remodel](remodel/README.md) | 用旧版人形的基本体重新生成连续曲面的人形与巡察者模型，以及死亡演出用的穿衣人形（`dress.py`）；需 numpy、scikit-image、fast-simplification |
| `audio_bake/bake.cjs` | 按旧版配方烘焙音频；需 Node、ffmpeg 与旧版源码 |

截图脚本集中在 `capture/`。CI 内部模块在 `ci/`，对开发者保留两个短入口 `check.py`、`export.py`。详细命令、日志位置与 Actions 下载方式见[项目结构与持续集成](../docs/项目结构与持续集成.md)。

校园加载基准默认使用已导入的源码工程。测量发行包时添加 `--main-pack /path/to/wdfz.pck`，在同一设备、画质、窗口尺寸和渲染器下分别运行两个版本。每组使用独立的临时用户目录，新局的开场动画统一在加载界面关闭后跳过。结果写入 `build/reports/campus-load/summary.json`，包括加载完成、首个可操作画面、加载期间最长一帧及穿门后首帧的耗时。基准同时检查出生点周围原有的八个预载模型和所有已登记区域的碰撞。`--display headless` 可测逻辑耗时，画面性能需要用窗口模式测量。
