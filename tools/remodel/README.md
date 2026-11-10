# 人形重建工具

把旧版（`wd-fz/wd-fz.github.io@0bf508a`）`model/figure.js` 的人形重新生成成一整张连续的曲面。旧版用六十多个椭球、圆台和倒角块拼一个人；逐块生成网格时接缝生硬。这里用同一批基本体（位置、半径都不改）做有向距离场的平滑并集，再取等值面。

```bash
pip install numpy scikit-image fast-simplification playwright
python3 tools/remodel/capture_primitives.py --old <旧仓库检出目录>   # 生成 primitives/figure_*.json（已入库，一般不用重跑）
python3 tools/remodel/remodel.py                                    # 写 assets/campus/figures/*.glb 与 patrol/patrol_figure.glb
godot --headless --path . --import
```

- `capture.js`／`capture_primitives.py`：在旧版页面里调用它自己的 `figGeo()`，只旁听 `Kit` 的基本体调用（`rod`、`blob`、`bevel`、`cyl`、`box`）并记下参数；旧版代码不改。为了走到基本体这条路，调用期间跳过模型包里的 `fig_*`。
- `remodel.py`：
  - 距离场：圆台按「圆头锥」、椭球、倒角块、圆柱各自的距离函数；平滑并集的融合半径按基本体的粗细取——四肢和手指（圆台）几乎不融，躯干、关节这些团块融得开，胸、腰、下摆连成一体。
  - 平滑并集在重叠处会鼓出最多 k／4，团块先收回这么多（不超过自身最小半径的四分之一），膝盖不会比大腿粗。
  - **无脸**：头上的眉骨、鼻子、耳朵三样小椭球不参加（用户选择「圆润无脸人形」）；头骨、头发的体积、下巴保留。
  - 3 毫米体素 marching cubes → 减到约 1 万三角面 → 法线取距离场梯度 → 顶点色烘一层凹处的暗（腋下、指缝、下巴底）。
  - 巡察者：老师体型 ×1.12、近黑色，外套和帽子沿用原模型里的第二个网格。
- 输出时会打印新旧包围盒（身高、肩宽、前后厚度）对照。Godot 导入器为网格生成 LOD，各画质档用已有的 LOD 阈值。

运行时不依赖这些 Python 包；只有重新生成模型的人需要。

平面窗户剪影单独保留 `assets/campus/figures/window_shadow.glb`：它是 `59ea7bb` 的原 `person.glb`，用于保持投影轮廓与原参考样本一致。重建脚本不会覆盖该文件；普通与怪异立体人物仍使用六种新网格。第一人称手经用户确认保留现有模型，不属于本工具输出。
