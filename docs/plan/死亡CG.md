# 死亡 CG

旧版 `fx/death-cg.js` 与各模块的 `DeathCG.register`（`wd-fz/wd-fz.github.io@0bf508a`）：按死因分镜，每种都是「前兆 → 接触／失控 → 临终视角 → 收束」，位置与镜头只由经过的时间算出（帧率高低结果一样）。Godot 版框架是 `app/death_cg.gd`（`DeathCG`）：布景放在「视线坐标系」（原点在玩家脚下，+z 是死亡那一刻的视线方向），镜头就是玩家自己的相机（只改俯仰、转向和抬高，演完还原），收束用相机上的一层暗场球；没有自己场景的死因仍用原来的画面特效渐隐。导出的手、头、长脖子的头等来自旧版 `fxMesh`（`tools/export_scenes/export_scenes.py --only fx`）。

## 待办与进度

旧版共 29 种（22 种在 `death-cg.js`，7 种在各模块里注册）；`death-cg.js` 里的 22 种与四种公开的模块分镜已移植。公开死因对应关系见 `StoryModule.DURATIONS`／`EPITAPH`。

| 死因 | 状态 |
| --- | --- |
| trash 垃圾桶、liftdoor 电梯门缝、grip 脚下伸手、neck 长脖子、shadow 影子、twin 另一个你、shatter 车铃炸开、drown 溺水、water 天花板渗水、freeze 冷库、stare 全体回头、voice 广播点名、bell 十三下钟、follow 做操的人、deep 食堂盛宴坠坑、floor 水杯、ring 圈、loop 无尽走廊、lamps 熄灯、laugh 笑、swarm 蛾群、gaze 拍肩 | 已完成（gaze 的眼睛是平的圆片，旧版有贴图精灵；swarm 的蛾翅是方片；floor 的杯子是简化的白杯＋淡紫盖，没有旧版杯身上的二校门图案） |
| window_gaze 窗内视线（7 秒）、paper_sender 纸飞机（8 秒）、misread 念错通知（4.1 秒）、campus_fall 坠落（6 秒） | 已完成（按死因的来源名选分镜，时长取各自的；字幕走左上角提示） |
| 旧版另有两处带隐藏内容的分镜 | 不在此表（按保密规则，只在内部计划里处理） |
| 其余的「画面特效渐隐」（vignette、names、chalk、slit、squeeze、face、wall、mirror、hand 等） | 旧版也没有独立分镜 |

## 差异

- 节拍声已接，时刻照旧版 `c.cue`：trash 三下门声（1.2／1.9／2.35 s）、grip 惊吓（1.5）、twin 消失（2.6）、gaze 身后笑声（1.75）、bell 大钟（1.45）、loop 惊吓（2.95）、lamps 八盏灯管依次噼啪（1.0 起每 0.15 s，越近越响）加最后一下惊吓（3.05）、laugh 突脸笑（2.6）；死亡时的总声音仍是原来的 `audio.death`。没有人耳试听。
- 垃圾桶是简化的桶（开口圆柱＋两道环），盖子合上后很暗是原设计（只剩盖沿一圈光）。
- 只在有画面的运行里演；无窗口（测试）仍走渐隐。

## 验收

`_test_death_cg`：已做的死因都有时长与分镜、缓动函数取值。截图 `pictures/死亡CG/`（每种三帧）。没有人耳试听。穿模检查：分镜都是视觉节点，不带碰撞。

## 成就、CG 与积分检查（CLAUDE.md）

只换演出，不改死因、判定与结算；不新增成就、死法。
