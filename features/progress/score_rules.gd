class_name ScoreRules
extends RefCounted
## Score, time score, grade and exploration of one run (domain/score-rules.js, reference
## wd-fz.github.io@0bf508a). Only judges, never changes play. The values are the Web version's provisional
## ones, kept in one place; RULES is written into every record so a later change only affects new records.

const RULES := 1
const PTS := {
	"ending": 300, "anomalyLethal": 40, "anomalyClean": 20, "anomalyHurt": -10,
	"noLaugh": 15, "laugh": -20, "faceRight": 10, "faceWrong": -15, "lesson": 5, "examPass": 20, "examFail": -10,
	"inspectOk": 20, "inspectAbsent": -30, "permanent": -80,
	"patrolLocked": -10, "patrolLockedCap": -60, "patrolLost": 10, "locker": 15,
	"protect": -60, "wake": -80,
	"sanLow": -30, "sanVeryLow": -30, "exploreEach": 2, "exploreCap": 200,
}
const SAN_LOW := 30.0
const SAN_VERY_LOW := 15.0
const HARD_MULT := 1.2
## Par time (s): 《网安仙人》 has a fixed 600 s wait after the wireless and the request.
const PAR := {"car": 1080, "face": 1200, "portal": 1320, "cyber": 1680, "dismissal": 1800, "beast": 600}
const TIME_BASE := 400.0
const TIME_MIN := 0.25
const TIME_MAX := 1.5
const EXPLORE_W := {"place": 0.5, "sketch": 0.3, "clue": 0.2}
## Nine grades: min is the lower bound of the grade score; band picks the sound group.
const GRADES := [
	{"g": "F", "min": 0, "name": "不及格", "band": "low", "memo": "卷子收上去了。名字那一栏是空的。"},
	{"g": "E", "min": 400, "name": "补考", "band": "low", "memo": "下一次，还是这间教室。"},
	{"g": "D", "min": 550, "name": "留级察看", "band": "low", "memo": "你走出来了，学校还记着你。"},
	{"g": "C", "min": 700, "name": "及格", "band": "mid", "memo": "及格。和大多数人一样。"},
	{"g": "B", "min": 850, "name": "良好", "band": "mid", "memo": "你记得每一条走廊。"},
	{"g": "A", "min": 1000, "name": "优秀", "band": "high", "memo": "它们没能留住你。"},
	{"g": "S", "min": 1150, "name": "表彰", "band": "high", "memo": "你比铃声快。"},
	{"g": "SS", "min": 1300, "name": "保送", "band": "top", "memo": "门在你面前，一次就开了。"},
	{"g": "SSS", "min": 1450, "name": "准予离校", "band": "top", "memo": "这一次，学校在你身后。"},
]
const CATS := ["结局", "成就", "应对 · 异象", "应对 · 选择", "校规与巡察", "SAN", "探索度", "保命与惊醒"]


static func time_score(sec: float, par: float) -> int:
	if not (sec > 0.0) or not (par > 0.0):
		return 0
	return roundi(TIME_BASE * clampf(par / sec, TIME_MIN, TIME_MAX))


static func grade_of(score: float) -> Dictionary:
	var out: Dictionary = GRADES[0]
	for g: Dictionary in GRADES:
		if score >= float(g["min"]):
			out = g
	return out


static func by_letter(letter: String) -> Dictionary:
	for g: Dictionary in GRADES:
		if g["g"] == letter:
			return g
	return {}


static func grade_index(letter: String) -> int:
	for i in GRADES.size():
		if GRADES[i]["g"] == letter:
			return i
	return -1


## SSS needs the nightmare difficulty, never being rescued, never waking from the foreseeing dream.
static func gate(ctx: Dictionary) -> bool:
	return ctx.get("diff", "easy") == "hard" and not bool(ctx.get("saved", false)) and not (int(ctx.get("wakes", 0)) > 0)


## x: places, places_total, cells, cells_total, clues, clues_total → {pct, place, sketch, clue}.
static func explore(x: Dictionary) -> Dictionary:
	var r := func(n: float, of: float) -> float: return clampf(n / of, 0.0, 1.0) if of > 0.0 else 0.0
	var place: float = r.call(float(x["places"]), float(x["places_total"]))
	var sketch: float = r.call(float(x["cells"]), float(x["cells_total"]))
	var clue: float = r.call(float(x["clues"]), float(x["clues_total"]))
	return {"pct": roundi(100.0 * (place * EXPLORE_W["place"] + sketch * EXPLORE_W["sketch"] + clue * EXPLORE_W["clue"])),
		"place": roundi(place * 100.0), "sketch": roundi(sketch * 100.0), "clue": roundi(clue * 100.0)}


## Merge like entries: "desk answer right ×3".
static func group(items: Array) -> Array:
	var out: Array = []
	var at := {}
	for it: Dictionary in items:
		var k := "%s|%s|%s" % [it["cat"], it["text"], it["pts"]]
		if at.has(k):
			out[at[k]]["n"] = int(out[at[k]]["n"]) + 1
			continue
		at[k] = out.size()
		out.append({"cat": it["cat"], "text": it["text"], "pts": int(it["pts"]), "n": 1})
	return out


## ledger: this run's entries [{cat, text, pts}]; ctx: ending (bool), ending_name, achievements [{name, pts}], san,
## min_san, explore {pct}, diff.
static func total(ledger: Array, ctx: Dictionary) -> Dictionary:
	var items: Array = ledger.duplicate(true)
	if bool(ctx.get("ending", false)):
		items.push_front({"cat": "结局", "text": String(ctx.get("ending_name", "通关")), "pts": PTS["ending"]})
	for a: Dictionary in ctx.get("achievements", []):
		if int(a.get("pts", 0)) != 0:
			items.append({"cat": "成就", "text": a["name"], "pts": int(a["pts"])})
	if ctx.get("san") != null:
		items.append({"cat": "SAN", "text": "最终状态", "pts": roundi(clampf(float(ctx["san"]), 0.0, 100.0))})
		if float(ctx.get("min_san", 100.0)) < SAN_LOW:
			items.append({"cat": "SAN", "text": "一度动摇", "pts": PTS["sanLow"]})
		if float(ctx.get("min_san", 100.0)) < SAN_VERY_LOW:
			items.append({"cat": "SAN", "text": "差一点崩溃", "pts": PTS["sanVeryLow"]})
	if ctx.get("explore") is Dictionary:
		items.append({"cat": "探索度", "text": "探索度 %d%%" % int(ctx["explore"]["pct"]), "pts": mini(int(PTS["exploreCap"]), int(ctx["explore"]["pct"]) * int(PTS["exploreEach"]))})
	var sum := 0
	for it: Dictionary in items:
		sum += int(it["pts"])
	var mult := HARD_MULT if ctx.get("diff", "easy") == "hard" else 1.0
	return {"items": group(items), "sum": sum, "mult": mult, "total": maxi(0, roundi(float(sum) * mult))}


## Grade score = score + time score; enough for SSS without the gate gives SS.
static func rate(score: float, sec: float, par: float, ctx: Dictionary) -> Dictionary:
	var t := time_score(sec, par)
	var gs := score + t
	var g := grade_of(gs)
	var ok := gate(ctx)
	var capped := false
	if g["g"] == "SSS" and not ok:
		g = by_letter("SS")
		capped = true
	return {"timeScore": t, "gradeScore": roundi(gs), "grade": g["g"], "gradeName": g["name"], "band": g["band"], "memo": g["memo"], "gate": ok, "capped": capped}


static func band(letter: String) -> String:
	var g := by_letter(letter)
	return String(g["band"]) if not g.is_empty() else "mid"


## The SAN state shown first on the result page (the exact value stays in the expanded detail).
static func san_band(v: float) -> String:
	return "清醒" if v >= 60.0 else ("动摇" if v >= 30.0 else "濒临")


## A sample breakdown that puts the grade score in the middle of the grade's range (the debug panel and the
## archive's directly-unlocked result screens; SSS/SS use the nightmare, never rescued, never woken).
static func sample(letter: String, par: float) -> Dictionary:
	var x: Dictionary = by_letter(letter) if not by_letter(letter).is_empty() else GRADES[0]
	var i := grade_index(String(x["g"]))
	var hi: float = float(GRADES[i + 1]["min"]) if i + 1 < GRADES.size() else float(x["min"]) + 200.0
	var target := roundi((float(x["min"]) + hi) / 2.0)
	var hard := letter == "SSS" or letter == "SS"
	var mul: float = {"F": 3.2, "E": 2.4, "D": 1.8, "C": 1.4, "B": 1.15, "A": 1.0, "S": 0.9}.get(letter, 0.8)
	var sec := roundi(par * float(mul))
	var t := time_score(sec, par)
	var want := target - t
	var mult := HARD_MULT if hard else 1.0
	var base := roundi(float(want) / mult)
	var items: Array = [{"cat": "结局", "text": "通关", "pts": PTS["ending"]}]
	var left: int = base - int(PTS["ending"])
	var san := clampi(roundi(40.0 + float(left) * 0.1), 5, 100)
	items.append({"cat": "SAN", "text": "最终状态", "pts": san})
	left -= san
	items.append({"cat": "应对 · 异象", "text": "调试示例", "pts": left})
	var sum := 0
	for it: Dictionary in items:
		sum += int(it["pts"])
	return {"items": items, "sum": sum, "mult": mult, "total": maxi(0, roundi(float(sum) * mult)), "sec": sec, "diff": "hard" if hard else "easy", "san": san}


## A complete sample record for a grade (not played: source "debug" until the app marks it).
static func sample_meta(letter: String, route: String, diff: String = "") -> Dictionary:
	var par := float(PAR.get(route, 1200))
	var smp := sample(letter, par)
	var d := diff if diff != "" else String(smp["diff"])
	var ctx := {"diff": "hard" if letter == "SSS" or letter == "SS" else d, "saved": false, "wakes": 0}
	var r := rate(float(smp["total"]), float(smp["sec"]), par, ctx)
	return {"id": "", "at": int(Time.get_unix_time_from_system() * 1000.0), "mode": "normal", "diff": ctx["diff"], "talent": "tech", "route": route, "routeName": route,
		"day": 1, "clock": 900.0, "time": {"active": float(smp["sec"]), "rta": null, "par": par, "used": float(smp["sec"])},
		"score": {"rules": RULES, "total": smp["total"], "sum": smp["sum"], "mult": smp["mult"], "items": group(smp["items"])},
		"grade": r["grade"], "gradeName": r["gradeName"], "band": r["band"], "memo": r["memo"], "gradeScore": r["gradeScore"], "timeScore": r["timeScore"], "gate": r["gate"],
		"capped": r["capped"], "explore": {"pct": 40, "place": 45, "sketch": 30, "clue": 40}, "san": {"final": smp["san"], "min": maxi(5, int(smp["san"]) - 30)},
		"ach": {"run": [], "newly": []}, "legacy": 0, "source": "debug", "version": "", "rated": true, "debug": false}
