# 死亡 CG

旧版 `fx/death-cg.js` 与各模块的 `DeathCG.register`（`wd-fz/wd-fz.github.io@0bf508a`）：按死因分镜，每种都是「前兆 → 接触／失控 → 临终视角 → 收束」，位置与镜头只由经过的时间算出（帧率高低结果一样）。Godot 版框架是 `game/presentation/cinematics/death_cg.gd`（`DeathCG`）：布景放在「视线坐标系」（原点在玩家脚下，+z 是死亡那一刻的视线方向），镜头就是玩家自己的相机（只改俯仰、转向和抬高，演完还原），收束用相机上的一层暗场球；没有自己场景的死因仍用原来的画面特效渐隐。导出的手、头、长脖子的头等来自旧版 `fxMesh`（`tools/export_scenes/export_scenes.py --only fx`）。

## 待办与进度

当前 `DeathCG.CAUSES` 接入 38 种本体效果与 1 种规则 DLC 效果：包括原分镜注册项及另外九种 `anfx` 死亡道具。接入数量不等于每种模型和画面均完成精确对照；下面保留已知的简化表现。死因对应关系见 `StoryModule.DURATIONS`／`EPITAPH`。

| 死因 | 状态 |
| --- | --- |
| trash 垃圾桶、liftdoor 电梯门缝、grip 脚下伸手、neck 长脖子、shadow 影子、twin 另一个你、shatter 车铃炸开、drown 溺水、water 天花板渗水、freeze 冷库、stare 全体回头、voice 广播点名、bell 十三下钟、follow 做操的人、deep 食堂盛宴坠坑、floor 水杯、ring 圈、loop 无尽走廊、lamps 熄灯、laugh 笑、swarm 蛾群、gaze 拍肩 | 主体分镜已接入；floor 已恢复原二校门杯身与杯盖，gaze 使用原眼睛贴图和张眼动画，swarm 使用原曲线翅形、灯晕及镜像扑翅。三者已按原运行时逐帧对照；其余主体分镜继续核对 |
| window_gaze 窗内视线（7 秒）、paper_sender 纸飞机（8 秒）、misread 念错通知（4.1 秒）、campus_fall 坠落（6 秒） | 已完成（按死因的来源名选分镜，时长取各自的；字幕走左上角提示） |
| crowd 电梯满员、void 与 abyss 特殊空间 | 分镜与规则已由 `CrowdDeath`／`MazeDeath` 接入；原运行时样本见迁移一致性验证 |
| vignette、names、chalk、slit、squeeze、face、wall、mirror、hand | 原版由 anfx 构建的九种死亡道具，现由 `RemainingDeathProps` 复现；不是只有渐隐。27 组机位、243 个状态逐项对照 |
| rules_knock | 规则 DLC 七秒专属分镜；原运行时 141 帧对照 |

## 差异

- 节拍声已接，时刻照旧版 `c.cue`：trash 三下门声（1.2／1.9／2.35 s）、grip 惊吓（1.5）、twin 消失（2.6）、gaze 身后笑声（1.75）、bell 大钟（1.45）、loop 惊吓（2.95）、lamps 八盏灯管依次噼啪（1.0 起每 0.15 s，越近越响）加最后一下惊吓（3.05）、laugh 突脸笑（2.6）；死亡时的总声音仍是原来的 `audio.death`。没有人耳试听。
- 垃圾桶是简化的桶（开口圆柱＋两道环），盖子合上后很暗是原设计（只剩盖沿一圈光）。
- 只在有画面的运行里演；无窗口（测试）仍走渐隐。

## 验收

`_test_death_cg`：已做的死因都有时长与分镜、缓动函数取值。截图 `pictures/死亡CG/`（每种三帧）。没有人耳试听。穿模检查：分镜都是视觉节点，不带碰撞。

## 成就、CG 与积分检查（CLAUDE.md）

只换演出，不改死因、判定与结算；不新增成就、死法。

调试预览使用独立相机与声音随机序列，真实死亡、关闭、传送、读取、新局和菜单清理；档案回放有独立会话与资料边界。验证覆盖见 `tests/suites/remaining_death.gd`、`debug_tools.gd`、`archive.gd` 与 `rules_dlc.gd`。历史 29 项的早期说明不能代表当前总量，自动化仍不代替实际听感和全部主体分镜的画面核对。

## 水杯、拍肩与蛾群模型对照

2026-11-08：直接运行原版三种分镜，各采样十个时刻，核对杯盖脱落、镜头、眼睛开合与透明度、70 只蛾的身体及 140 片翅膀变换。预览沿用独立相机，不改变正式玩家位置和朝向。无窗口专项 **128 项检查、0 失败**，原生窗口专项 **172 项检查、0 失败**；实例矩阵回读需要真实渲染器，因此只在原生窗口验证，不能用无窗口的占位矩阵冒充结果。

横屏实拍入口 `tools/capture/capture_death_models.gd`。只核销这三种模型的已知占位；垃圾桶等主体细节、其余随机布景与实际听感仍需继续核对。详见[迁移一致性验证](../迁移一致性验证.md)。
