# 开发工具

| 入口 | 用途 |
| --- | --- |
| `python tools/export_reference.py --source <旧版目录> --chromium <浏览器路径>` | 从真实 Web 运行时生成碰撞、课表、镜头和画质对照样本；正常 CI 直接读取已提交样本 |
| `python tools/check.py` | 结构、依赖边界、真实 Godot 导入与回归 |
| `python tools/export.py` | Linux／Windows 开发包与 Linux Vulkan 启动／包内容检查（需显示服务） |
| `python tools/export_android.py` | Linux 上生成并验证签名 Android Debug APK（ARM64） |
| `python tools/ci/install_godot.py --templates` | Linux 上安装固定版本官方引擎和两个桌面 release 模板 |
| `python tools/ci/install_godot.py --android-debug` | 安装同版本 Android Gradle 模板与预编译引擎库 |
| `godot --windowed --path . --script res://tools/capture/capture_campus.gd` | 实际渲染校园截图，需要显示服务 |
| [export_scenes](export_scenes/README.md) | 从旧 Web 版导出建筑、贴图、布局与世界登记 |
| [remodel](remodel/README.md) | 用旧版人形的基本体重新生成连续曲面的人形与巡察者模型；需 numpy、scikit-image、fast-simplification |
| `audio_bake/bake.cjs` | 按旧版配方烘焙音频；需 Node、ffmpeg 与旧版源码 |

截图脚本集中在 `capture/`。CI 内部模块在 `ci/`，对开发者保留两个短入口 `check.py`、`export.py`。详细命令、日志位置与 Actions 下载方式见[项目结构与持续集成](../docs/项目结构与持续集成.md)。
