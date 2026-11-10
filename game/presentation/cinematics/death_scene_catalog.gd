class_name DeathSceneCatalog
extends RefCounted
## Presentation identities are separate from gameplay FX and persistent death sources.
## [title, set / action family, seconds]. Replays resolve the same source as live deaths.
const SCENES := {
	"patrol":["巡察者 · 最后一次点名","rollcall",4.8],
	"garage":["车库 · 灯下的长影","garage",4.8],
	"car_entry":["后座 · 多出的乘客","backseat",4.6],
	"car_chase":["追车 · 路的尽头","crash",4.6],
	"san":["失神 · 教室被擦去","classroom",5.0],
	"assimilation":["同化 · 永久留座","classroom",5.0],
	"trap_out":["正门 · 重复的出口","corridor",4.6],
	"trap_wall":["围墙 · 合拢的缝隙","corridor",4.6],
	"trap_beg":["问路人 · 没有脸的方向","face",4.6],
	"trash":["垃圾房 · 从里面关上","trash",4.4],
	"liftdoor":["电梯 · 门缝里的来客","door",4.8],
	"crowd":["满员 · 遗落的学生证","crowd",4.2],
	"grip":["拘留 · 被划去的名字","rollcall",4.6],
	"neck":["围栏 · 越过横杆的头","fence",4.8],
	"shadow":["黑影 · 最后一束灯光","garage",4.6],
	"twin":["分身 · 迟到半拍","double",4.8],
	"shatter":["破裂 · 玻璃后的世界","crash",4.6],
	"drown":["暴雨 · 水面越过视线","flood",4.8],
	"water":["积水 · 颠倒的窗光","flood",4.8],
	"freeze":["寒冷 · 挂起的校服","frost",4.6],
	"stare":["注视 · 全班转头","classroom",4.8],
	"voice":["广播 · 只剩下你的声音","broadcast",4.6],
	"bell":["钟声 · 停在最后一下","bell",4.8],
	"follow":["队列 · 多出来的位置","assembly",4.8],
	"deep":["食堂 · 永远到不了的餐桌","banquet",4.8],
	"floor":["水杯 · 杯口成为天空","cup",4.8],
	"ring":["仪式 · 空缺被补齐","ritual",4.8],
	"loop":["走廊 · 出口退后一步","corridor",4.8],
	"lamps":["灯列 · 黑暗逐盏走近","corridor",4.8],
	"laugh":["笑声 · 笑容越过边框","face",4.6],
	"swarm":["蛾群 · 扑灭最后的灯","swarm",4.8],
	"gaze":["拍肩 · 回头的人","face",4.8],
	"window_gaze":["窗外 · 玻璃上的呼吸","face",5.2],
	"paper_sender":["纸飞机 · 飞回来的信","paper",5.0],
	"misread":["通告 · 最后一行字","broadcast",4.6],
	"campus_fall":["坠落 · 向上流动的窗","fall",4.6],
	"void":["迷失 · 没有出口的白廊","void",3.6],
	"abyss":["深渊 · 最后的落脚点","abyss",3.6],
	"vignette":["失焦 · 空下来的课桌","classroom",4.6],
	"hand":["后排 · 肩膀上的重量","backseat",4.6],
	"names":["名册 · 下一行是你","rollcall",4.6],
	"chalk":["黑板 · 擦不掉的人影","classroom",4.6],
	"mirror":["镜面 · 倒影先动了","mirror",4.8],
	"face":["面孔 · 多出来的笑","face",4.6],
	"squeeze":["窄廊 · 墙在呼吸","corridor",4.6],
	"slit":["纸缝 · 另一面的眼睛","paper",4.6],
	"wall":["墙面 · 被抹掉的门","corridor",4.6],
	"rules_knock":["寝室 · 门外第三声","door",5.4],
}

const SOURCE_SCENES := {
	"an:rain":"drown", "an:moth":"swarm", "an:exercise":"follow",
	"an:rite":"ring", "an:necker":"neck", "an:twin":"twin", "an:cup":"floor",
	"void_lost":"void", "void_fall":"abyss", "x.rules.knock":"rules_knock",
}

static func resolve(source: String, effect: String) -> String:
	if SCENES.has(source): return source
	if SOURCE_SCENES.has(source): return String(SOURCE_SCENES[source])
	return effect if SCENES.has(effect) else ""

static func title(id: String) -> String:
	return String(SCENES[id][0]) if SCENES.has(id) else id

static func layout(id: String) -> String:
	return String(SCENES[id][1]) if SCENES.has(id) else ""

static func lengths() -> Dictionary:
	var result := {}
	for id: String in SCENES: result[id] = float(SCENES[id][2])
	return result
