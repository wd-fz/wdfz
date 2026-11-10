# 测试截图索引

按 `CLAUDE.md` 约定，每次改动的测试截图放在 `pictures/<轮次或主题>/`，文件名写清楚内容，并在下表加一行。截图记录视口、渲染方式、画质、地点、操作和是否注入状态；截图只能证明所显示的画面，不能替代断言或完整游玩。

框架阶段（PR #1）的截图在 `docs/images/`，这里不重复收录。

| 目录 | 内容 |
| --- | --- |
| [迁移一致性](迁移一致性) | 原场景边界修复、触屏与特殊空间、隐藏演出等迁移验证；具体批次与限制见[迁移一致性验证](../docs/迁移一致性验证.md)。2026-11-08 新增《盗梦空间》：Godot 4.6.3 Compatibility / Mesa llvmpipe，1280×720；`tools/capture/capture_inception.gd` 经实际拾取、睡眠与坠落触发，注入机位、随机值和 CG 进度，无后期调色。 |
| [正式校园建筑](正式校园建筑) | 2026-11-06，Godot 4.6.3，Xvfb + Compatibility（Mesa llvmpipe 软件渲染），1280×720，`tools/capture/capture_campus.gd` 直接摆放机位（注入位置，非自然行走）。灯光是占位环境光，不代表旧版灯光：教学楼 1F 开局起身位置、走廊、南门门槛（门外黑——门里看门外的表现尚未移植）、室外教学楼正门与行政楼方向、行政楼 1F、食堂、北宿舍 1F、地下车库、钟楼 |
| [楼层通行与校园日程](楼层通行与校园日程) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_campus.gd` 注入机位，占位灯光：西楼梯井一楼平台、连廊二、教学楼一楼电梯门与「E · 电梯」提示、开局教室的 HUD（地点、时段、时间不明） |
| [灯光](灯光) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_lighting.gd` 注入时刻与机位：教学楼 1F 教室 11:40 与 23:00、教学楼前 11:40、19:10、23:20。对照旧仓库 `pictures/恐怖氛围加强/` 校准换算系数，仍是近似（没有旧版后期的颗粒、暗角与 SAN 画面） |
| [巡察者](巡察者) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，注入机位与巡察者位置：教学楼 1F 走廊里迎面走来的巡察者；躲在储物柜里的柜缝画面与「E · 出来」提示 |
| [异象](异象) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_anomaly.gd` 强制开启异象：教学楼走廊平常与停电；操场平常与大暴雨（天色压暗、浓雾） |
| [结局路线](结局路线) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_routes.gd` 注入状态与机位：西小门闸机与交互提示、白名单验证第 1 题、三题答完闸机亮绿灯、《白名单》真结局卡 |
| [异象画面](异象画面) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_anomaly.gd` 强制开启异象并注入数据：操场的大暴雨雨线、做操的人群、仪式圈与蜡烛、黑板字（占位几何，无声音） |
| [成就](成就) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_menu.gd` 注入解锁：主菜单（成就与声音按钮），成就列表（解锁显示回忆句、未解锁只显示名称） |
| [死亡演出](死亡演出) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_death.gd` 以固定进度 0.7 直接显示叠层（非真实死亡流程）：收拢暗角、水面上涨、闪烁斑点、两侧压来 |
| [车库与开车](车库与开车) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_garage.gd` 注入位置与驾驶状态：手电照着车道上的黑影；校外道路上的路障与「出城／回校」路牌（占位几何） |
| [设施与传送门](设施与传送门) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_portal.gd` 注入位置与门已打开的状态：物理实验室隧道；实验台前撑开的光圈（占位） |
| [广播与放学](广播与放学) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_broadcast.gd` 注入位置与长铃状态：广播站菜单；离校人群走向北门（占位胶囊体）；`tools/capture/capture_mic.gd`：话筒面板（四页稿在手、正在朗读，进度条、「松开停播」，门禁已上报的提示） |
| [手机与网安仙人](手机与网安仙人) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_terminal.gd` 注入手机已联网的状态，通过界面信号输入三条命令：机房电脑的模拟 Linux 终端 |
| [天赋](天赋) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720 与 720×1280，`tools/capture/capture_menu.gd`：新游戏的天赋选择（横屏、竖屏可滚动） |
| [异象画面](异象画面)（第二批） | 2026-11-07，同上设置，`tools/capture/capture_anomaly.gd`：走廊里全体回头的脸、盛宴长桌与碗碟热气（占位几何） |
| [天赋](天赋)（开场） | 2026-11-07，同上：前情提要的一页 |
| [同学](同学) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_classroom.gd`：开局座位看到的同学；注入违规 75 后全班转向我（占位胶囊体） |
| [感官反馈](感官反馈) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_sensory.gd`：教学楼 1F 同一走廊在 SAN 100、35、8 时的画面（收窄、失焦、褪色、灯管灯晕；2026-11-07 换成照旧版公式的新着色器） |
| [体检日](体检日) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_checkup.gd` 注入第三天为体检日、10:25：行政楼一楼走廊排队的人与门牌、身高尺与体重秤、视力表（占位几何） |
| [声音字幕](声音字幕) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_captions.gd`：教学楼 1F，下课铃与左侧隔墙的敲门声的字幕 |
| [氛围](氛围) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_dread.gd`：同一天第二次回到教学楼 1F 时地上的纸条（回访变化）；`tools/capture/capture_atmos.gd`（第三天傍晚）：走廊暗区与墙边拖把水桶、拖把转过来对着我、教室窗外远处的人影、楼梯口上方的应急指示牌（占位几何；同学一起转头在占位胶囊上看不出来，由规则测试覆盖） |
| [设置](设置) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_settings.gd`：主菜单上打开的设置面板（声音、画面与舒适、操作与文字三组，滚动查看） |
| [调查笔记](调查笔记) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_notes.gd`：读过停车单与移交单、保安岗登记之后的笔记页（当前调查、最近发现、按类型分组的记录） |
| [地图](地图) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_map.gd`：沿教学楼一楼走廊走过一遍后的楼层草图（只画看见过的格子，已看清 54%）；校园总图（建筑、三个校门、玩家位置与朝向） |
| [手机外壳](手机外壳) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_phone.gd`：手机外壳的主页与无线接入页、纸飞机小游戏（结束画面）、相机页拍了两张之后的相册（缩略图带时钟戳） |
| [机房贪吃蛇](机房贪吃蛇) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_snake.gd`：机房电脑旁的贪吃蛇走到墙边结束（得分 3），下面是触屏方向键 |
| [值日表](值日表) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_duty.gd`：教学楼一楼第一间教室黑板旁的值日表，同化 0、2、4 档（4 档整张表只剩连笔的「名字」） |
| [结算画面](结算画面) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_results.gd`：用示例记录（不是真实通关）拍的结算页（B）与九档评级画面中的 F、E、D、C、A、S、SS、SSS（B 在结算页里）；揭示动画拍的是最后一帧 |
| [通关记录](通关记录) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_records.gd`：用示例记录（不是真实通关）拍的通关记录列表（难度／路线筛选、四种排序）、地图回放（脚印、巡察者轨迹、事件列表、播放条）与足迹图 |
| [人形模型](人形模型) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_figures.gd`、`tools/capture/capture_classroom.gd`：旧版 `figure.js` 导出的六种人形（tall／roam／person／teacher／neck／sit）并排；教室里同学换成坐姿人形（面向黑板），同化高时整班转头 |
| [第一人称手部](第一人称手部) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_hands.gd`：右手手电、左手撑开的雨伞加右手手电、手机（旧版 `hands.js` 导出的手与袖口） |
| [第一人称手部](第一人称手部) 续 | 2026-11-08，同上，`tools/capture/capture_hands.gd`：手只受环境光和自己的近光灯照（旧版手单独一个场景），手电亮着时近光更强、灯头发暖光；文件名带「自带近光」 |
| [开场CG](开场CG) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_opening.gd`：新局开场的实时分镜各段（后排推向讲台、老师念到一半、粉笔灰停在半空、镜头转向「你」、趴下、醒来）；取的是分镜某一时刻的静帧 |
| [结局分镜](结局分镜) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_endings.gd`：公开结局《白名单》的实时分镜（闸机灯红、变白、转身、门里站满看着你的人）；分镜某一时刻的静帧 |
| [校庆横幅](校庆横幅) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_banner.gd`：校庆日教学楼正面二楼的红底黄字横幅（树挡了一部分） |
| [粉笔预告与逃课字](粉笔预告与逃课字) | 2026-11-07，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_chalk.gd`：异象来临前写在黑板上的预告时刻（Label3D 粉笔白字）；违规高、在不对的地方时地上与墙上冒出的逃课警告字（右下角小字，较淡） |
| [菜单照片](菜单照片) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_menu_photo.gd`：22:18 夜里的校园（菜单背景的原图），以及放进主菜单后的样子 |
| [结局分镜](结局分镜) 续 | 2026-11-08，同上，`tools/capture/capture_endings_intl.gd`：公开结局《外国语学生》的四个舞台（访客过北门、门卫核对名单、门外递还接待证、接待证上陌生的校名） |
| [结局分镜](结局分镜) 续二 | 2026-11-08，同上，`tools/capture/capture_endings_dis.gd`：公开结局《放学》的四个舞台（广播间、全班起立、楼梯井人流、北门与教学楼）；取的是分镜某一时刻的静帧 |
| [结局分镜](结局分镜) 续三 | 2026-11-08，同上，`tools/capture/capture_endings_portal.gd`：公开结局《门》（简化的装置：充能、导轨闭合、门开、推进环面发白） |
| [结局分镜](结局分镜) 续四 | 2026-11-08，同上，`tools/capture/capture_endings_cyber.gd`：公开结局《网安仙人》（简化布景：机柜指示灯与停机日志、走廊灯管闪与高个子垂肩、档案对照屏、天亮） |
| [结局分镜](结局分镜) 续五 | 2026-11-08，同上，`tools/capture/capture_dismissal.gd`／`capture_cyber.gd`／`capture_portal_device.gd`（文件名带 `real`）：《放学》最后一段改在真实校园里（北门、教学楼前）；《网安仙人》机房／走廊／档案换成导出的设备模型、天亮在真实校园；《门》在真实物理实验室里用整台装置（充能、门开、推进环面） |
| [结局分镜](结局分镜) 续六 | 2026-11-08，同上：实验室里常驻的传送门装置三种状态（`portal-live-1-base`／`-2-ready`／`-3-open`，取代原来的光圈）；《网安仙人》档案屏改成画布（红框圈出三处矛盾、「≠」、最后一行）；分镜演出时 HUD 隐藏 |
| [结局分镜](结局分镜) 续七 | 2026-11-08，`tools/capture/capture_endings_car.gd`：《闸门》片头在真实车库（车灯光圈）与真实室外北门（黑影涌出）（文件名带 `real`） |
| [结局分镜](结局分镜) 续五 | 2026-11-08，同上，`tools/capture/capture_endings_car.gd`：《闸门》开车前的片头（车库里车灯闪、门外黑影追出来；简化布景） |
| [死亡CG](死亡CG) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_death.gd`：按死因的死亡演出各取 25%／55%／85% 三帧（trash 垃圾桶、liftdoor 电梯门缝、grip 脚下伸手、neck 长脖子、shadow 影子、twin 另一个你、shatter 车铃炸开、drown 溺水、water 天花板渗水、freeze 冷库、stare 全体回头、voice 广播点名、bell 十三下钟、follow 做操的人、deep 食堂盛宴坠坑、floor 水杯、ring 圈、loop 无尽走廊、lamps 熄灯、laugh 笑、swarm 蛾群、gaze 拍肩、window_gaze 窗内视线、paper_sender 纸飞机、misread 念错通知、campus_fall 坠落） |
| [粉笔笔触](粉笔笔触) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_chalk_marks.gd`：八种粉笔符号的贴图（灰边白芯、断续线条、颗粒），以及贴在教室黑板上的叉 |
| [笑脸与幻觉](笑脸与幻觉) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_phantoms.gd`：拍肩的另一种——回头时身后一米多的笑脸（点头淡出）与不回头时的突脸（撑满视野） |
| [广播站道具](广播站道具) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_broadcast_props.gd`：行政楼二楼广播站的功放、话筒、记录本与「功放保险丝已烧」的牌子 |
| [连廊互看](连廊互看) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_link_view.gd`：站在连廊一里朝两头看，对面那栋楼的模型按端口的刚性变换摆进来，门洞里补了一盏灯 |
| [旧存档导入](旧存档导入) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_import.gd`：主菜单「导入旧存档」面板（粘贴旧版 JSON，不合法时显示原因） |
| [镜中轮廓](镜中轮廓) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_mirror.gd`：教学楼洗手池上方的镜子，SAN 高时轮廓与你同步；SAN 极低时它先抬起一只手 |
| [午夜食堂](午夜食堂) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_canteen.gd`：熄灯后食堂里唯一亮着的灯、地上的光圈与背对着你的打饭的人 |
| [医务室药柜](医务室药柜) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_clinic.gd`：行政楼一楼西头第一间办公室（医务室）墙上带红十字的药柜 |
| [驾驶仪表盘](驾驶仪表盘) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，1280×720，`tools/capture/capture_drive.gd`：驾驶视角的仪表盘、方向盘与后视镜；追影远时镜里只有一个黑影，近时五个 |
| [异象留下的痕迹](异象留下的痕迹) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_traces.gd`：异象过后留在教室地上的积水、死飞蛾、脚印与散落的纸 |
| [楼梯井互看](楼梯井互看) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_stair_view.gd`：站在教学楼一楼走廊，从楼梯间门洞里看得见楼梯井 |
| [门内外互看](门内外互看) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_door_view.gd`：站在教学楼南门外，门洞里看得见一楼走廊与安全出口灯 |
| [楼梯井互看](楼梯井互看) 续 | 2026-11-08，同上，`tools/capture/capture_shaft.gd`：站在楼梯井二层平台，门洞外是教学楼二层走廊（随所在层只摆当前层与相邻一层） |
| [外廊看校园](外廊看校园) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_gallery.gd`：站在教学楼三楼敞开的外廊，红栏杆外是真实的校园与对面的楼 |
| [雨与蛾群](雨与蛾群) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_weather.gd`：异象「下雨」的雨丝（线段）、落地水圈与积水；「蛾群」的身子加两片会扑的翅膀 |
| [画质档](画质档) | 2026-11-08，Godot 4.6.3，Xvfb + Compatibility 软件渲染，`tools/capture/capture_tier.gd`：第 0 档（流畅）模型下的教学楼一楼教室 |
| [界面审美与光影](界面审美与光影/) | 2026-11-09，Godot 4.6.3，Xvfb + Vulkan（Lavapipe）Forward+，1280×720，`tools/capture/capture_polish.gd`：设置「键位」页（录入中）；触屏布局编辑器（逐个控件、选中「交互」放大到 130 %、网格吸附）与默认触屏布局；光影按画质档对照（流畅／精细／真实的教室白天，流畅／真实的室外傍晚，真实的室外白天；同一时刻、同一机位，平均亮度相近）；新版界面：主菜单、暂停、游戏内界面（时间与状态卡、物品栏、点状准星）、设置画面页、背包 |
| [建模与光影优化](建模与光影优化/) | 2026-11-10，Godot 4.6.3，Xvfb + Vulkan（Lavapipe）Forward+，1280×720：教室北窗的天光落在课桌与地面上（精细档）；开场教室（新人形、灯管不再过曝）；人形新旧对照（`build/dbg_fig.gd` 式的并排：路人、老师、高个子、长脖子、坐姿）与近景；里世界教室里同学的剪影 |
