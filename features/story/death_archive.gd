class_name DeathArchive
extends RefCounted
## CG archive of deaths and endings (death-archive.js DEATH_ARCHIVE / ARCHIVE_CUTS, reference
## wd-fz.github.io@0bf508a): every real cause of death gets a file the first time it happens and
## later deaths only add to a counter. Ported here: the public causes the ported systems can
## produce, and the public endings that exist. The replay stages and the death CG scenes
## (fx/death-cg.js) are not ported, so the archive is a record list, not a viewer.
## Hidden endings and the maze deaths are not part of this public table.

## [id, name, one-line record]; the id is the kill source ("an:<id>" for anomalies).
const DEATHS := [
	["patrol", "点名", "灯按拍子闪的时候，它就在这一层。一只手从后面按住了我的头顶。"],
	["san", "那根弦", "理智耗尽。一圈没有脸的高个子，从暗处一个接一个走出来。"],
	["assimilation", "合身的椅子", "我在自己的位子上坐好了。这一次，不用再起来了。"],
	["trash", "桶盖", "桶盖合上了。外面有人敲了两下，像在确认里面有没有人。"],
	["liftdoor", "没关上的门", "门只剩一掌宽的时候，四根手指伸了进来。楼层灯停在这一层，门合上，轿厢里没有人。"],
	["an:rain", "雨", "雨灌进了肺里。我听见自己在身体里晃。"],
	["an:moth", "蛾群", "翅膀上的粉落进眼睛里，很痒。然后什么都不痒了。"],
	["an:exercise", "课间操", "我开始跟着做操。手臂抬起来的时候才发现，早就停不下来了。"],
	["an:rite", "粉笔圈", "圈正中那个空着的位置，刚好是我的大小。"],
	["an:necker", "围栏的缝", "他没有绕到校门口。他把脖子从围栏的缝里伸了进来。"],
	["an:twin", "天台的另一头", "他走到了我面前。我们同时抬起手。他的手是热的。"],
	["an:cup", "窗台上的杯子", "一只白色的杯子，画着二校门。它比我想象的要重。"],
]
const ENDS := [["face", "《白名单》", "闸机的红灯「嘀」地变白。走出门回头，门里一个接一个站满了目送的人。"]]


## record: the death log's "sources" counts; ends: the ending record ({id: 1}).
static func rows(record: Dictionary, ends: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sources: Dictionary = record.get("sources", {})
	var no := 1
	for d: Array in DEATHS:
		var n := int(sources.get(d[0], 0))
		out.append({"no": no, "name": d[1], "on": n > 0, "count": n, "memo": d[2]})
		no += 1
	for e: Array in ENDS:
		var seen := ends.has(e[0])
		out.append({"no": no, "name": e[1], "on": seen, "count": 1 if seen else 0, "memo": e[2]})
		no += 1
	return out


static func known(rows_in: Array[Dictionary]) -> int:
	return rows_in.filter(func(r: Dictionary) -> bool: return r["on"]).size()
