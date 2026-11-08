# 死亡 CG

旧版 `fx/death-cg.js` 与各模块的 `DeathCG.register`（`wd-fz/wd-fz.github.io@0bf508a`）：按死因分镜，每种都是「前兆 → 接触／失控 → 临终视角 → 收束」，位置与镜头只由经过的时间算出（帧率高低结果一样）。Godot 版框架是 `app/death_cg.gd`（`DeathCG`）：布景放在「视线坐标系」（原点在玩家脚下，+z 是死亡那一刻的视线方向），镜头就是玩家自己的相机（只改俯仰、转向和抬高，演完还原），收束用相机上的一层暗场球；没有自己场景的死因仍用原来的画面特效渐隐。导出的手、头、长脖子的头等来自旧版 `fxMesh`（`tools/export_scenes/export_scenes.py --only fx`）。

## 待办与进度

旧版共 29 种（22 种在 `death-cg.js`，7 种在各模块里注册）。公开死因对应关系见 `StoryModule.DURATIONS`／`EPITAPH`。

| 死因 | 状态 |
| --- | --- |
| trash 垃圾桶、liftdoor 电梯门缝、grip 脚下伸手、neck 长脖子、shadow 影子、twin 另一个你 | 已完成 |
| swarm、shatter、drown、water、freeze、gaze、stare、voice、bell、follow、deep、floor、ring、loop、lamps、laugh | 未做 |
| void、abyss（虚空迷宫）、campus_fall（坠落）、window_gaze（窗内视线）、crowd（电梯人群）、paper_sender（纸飞机）、misread（念错通知） | 未做 |
| 其余的「画面特效渐隐」（vignette、names、chalk、slit、squeeze、face、wall、mirror、hand 等） | 旧版也没有独立分镜 |

## 差异

- 没有 `SFX.door` 等分镜里的节拍声（死亡时的声音仍是原来的 `audio.death`）。
- 垃圾桶是简化的桶（开口圆柱＋两道环），盖子合上后很暗是原设计（只剩盖沿一圈光）。
- 只在有画面的运行里演；无窗口（测试）仍走渐隐。

## 验收

`_test_death_cg`：已做的死因都有时长与分镜、缓动函数取值。截图 `pictures/死亡CG/`（每种三帧）。没有人耳试听。穿模检查：分镜都是视觉节点，不带碰撞。

## 成就、CG 与积分检查（CLAUDE.md）

只换演出，不改死因、判定与结算；不新增成就、死法。
