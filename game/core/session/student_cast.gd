class_name StudentCast
extends RefCounted
## Playable roles are cosmetic. Talents and personal progression are independent.
const DEFAULT := "lin"
const IDS := ["lin", "qiao", "shen", "xu"]
const PEOPLE := {
	"lin": {"name": "林澈", "club": "摄影社", "line": "胶卷里多出的那个人，昨天还不在。", "color": "85b6d1", "height": 1.02},
	"qiao": {"name": "乔禾", "club": "田径队", "line": "我记得终点线在哪。就算天黑，也记得。", "color": "e38e79", "height": 0.98},
	"shen": {"name": "沈墨", "club": "物理课代表", "line": "走廊又长了两米。我量过三次。", "color": "aec58f", "height": 1.045},
	"xu": {"name": "许棠", "club": "校广播站", "line": "刚才广播里的声音，和我一模一样。", "color": "e5b875", "height": 0.96},
}


static func valid(value: Variant) -> bool:
	return value is String and PEOPLE.has(value)


static func resolve(value: Variant) -> String:
	return String(value) if valid(value) else DEFAULT
