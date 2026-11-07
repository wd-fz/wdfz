class_name BodyModule
extends FeatureModule
## Vaulting, injury and falling off the campus, ported from the Web version (reference
## wd-fz.github.io@0bf508a, modules/body/injury.js BODY_CFG / Body): the roof parapet of the
## teaching building and the railings of the two bridges can be climbed over (E and confirm); the
## roof is a fatal fall (中国人能飞), a bridge drops you on the ground outside with +45 injury.
## Injury 0–100: grazes heal standing still, 25+ slows to ×0.9, 60+ to ×0.8 and stops running and
## vaulting, stamina cap −0.4 per point, 100 kills. A medkit (4 s, still) heals 40; the clinic in
## admin1 hands out one a day. The dedicated fall CG (fall-death.js) is not ported.

const STATE_VERSION := 1
const VAULT_COST := 8.0
const LINK_INJURY := 45.0
const FALL_ROOF := 1.3
const FALL_LINK := 0.9
const MEDKIT := 40.0
const MEDKIT_TIME := 4.0
const REST_AFTER := 20.0
const REST_RATE := 1.0
const NO_RUN := 60.0
const STAM_PER := 0.4
const CLINIC := {"room": "admin1", "c": 6.0, "r": 15.85}

var injury := 0.0
var rest_t := 0.0
var treat: Variant = null     # {t}
var fall: Variant = null      # {kind, room, side, t, from {x, y, ang}}
var med_day: Dictionary = {}
var events: Array = []

var _c: Dictionary = {}
var _rooms: Dictionary = {}


func _init(rooms: Dictionary = {}) -> void:
	_rooms = rooms


func module_id() -> StringName:
	return &"body.injury"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	injury = 0.0
	rest_t = 0.0
	treat = null
	fall = null
	med_day = {}
	events = []


func capture() -> Dictionary:
	return {"injury": injury, "rest_t": rest_t, "med_day": med_day.duplicate()}


func validate(data: Dictionary) -> String:
	return "" if SaveSchema.number_in(data.get("injury", 0.0), 0, 100) else "伤势无效"


func restore(data: Dictionary) -> void:
	reset()
	injury = float(data.get("injury", 0.0))
	rest_t = float(data.get("rest_t", 0.0))
	med_day = (data.get("med_day", {}) as Dictionary).duplicate()


## ctx: scene, x, y, ang, seated, hiding, stam, moving, locked (patrol), anomaly, day.
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


func _say(text: String) -> void:
	_emit("notice", {"text": text})


func speed_mul() -> float:
	if injury >= 60.0:
		return 0.8
	if injury >= 25.0:
		return 0.9
	return 1.0


func can_run() -> bool:
	return injury < NO_RUN


func stamina_cap_drop() -> float:
	return injury * STAM_PER


func busy() -> bool:
	return fall != null or treat != null


func hurt(n: float, why: String) -> void:
	injury = clampf(injury + n, 0.0, 100.0)
	rest_t = 0.0
	_emit("hurt_fx")
	_emit("fact", {"what": "injury", "amount": n, "total": injury, "source": why})
	if injury >= 100.0:
		_emit("kill", {"msg": "我摔得太重，爬不起来了。", "fx": "campus_fall", "source": "campus_fall"})


## The railing in front of the player, or {} (Body.target).
func target() -> Dictionary:
	var scene := String(_c.get("scene", ""))
	if bool(_c.get("seated", false)) or bool(_c.get("hiding", false)) or not _rooms.has(scene):
		return {}
	var r: Dictionary = _rooms[scene]
	var kind := "roof" if scene == "teach6" else ("link" if r.get("host") in ["c1", "c2"] else "")
	if kind == "":
		return {}
	var ang := float(_c.get("ang", 0.0))
	var d := 0.85 * float(r["tw"])
	var p := Vector2(float(_c.get("x", 0.0)) + cos(ang) * d, float(_c.get("y", 0.0)) + sin(ang) * d)
	var c := int(floor((p.x - float(r["ox"])) / float(r["tw"])))
	var row := int(floor((p.y - float(r["oy"])) / float(r["th"])))
	var grid: Array = r["grid"]
	if row < 0 or row >= grid.size() or c < 0 or c >= String(grid[row]).length() or String(grid[row]).substr(c, 1) != "#":
		return {}
	var rows := int(r["rows"])
	var cols := int(r["cols"])
	var edge := (row == 0 or row == rows - 1 or c == 0 or c == cols - 1) if kind == "roof" else (c == 0 or c == cols - 1)
	if not edge:
		return {}
	return {"kind": kind, "room": scene, "side": -1 if c == 0 else (1 if c == cols - 1 else 0), "c": c, "r": row}


func hint() -> String:
	if not target().is_empty():
		return "翻过栏杆 · 外侧悬空"
	if near_clinic():
		return "医务室的药柜"
	return ""


## E in front of a railing: ask first.
func ask_vault() -> bool:
	var t := target()
	if t.is_empty():
		return false
	_emit("choice", {"text": "栏杆外面什么都没有。往下看，是很远的地面。" if t["kind"] == "roof" else "栏杆外面悬空，下面是一层楼高的地面。", "labels": ["翻过去", "算了"]})
	return true


func vault() -> bool:
	var t := target()
	if t.is_empty():
		return false
	if injury >= NO_RUN:
		_say("我：腿使不上劲，翻不过去。")
		return false
	if float(_c.get("stam", 100.0)) < VAULT_COST:
		_say("我：喘不过气来，先歇一下。")
		return false
	_emit("stamina", {"amount": -VAULT_COST})
	fall = {"kind": t["kind"], "room": t["room"], "side": t["side"], "t": 0.0, "from": {"x": float(_c.get("x", 0.0)), "y": float(_c.get("y", 0.0)), "ang": float(_c.get("ang", 0.0))}}
	_emit("fact", {"what": "vault_start", "kind": t["kind"]})
	return true


## How far the eye has dropped (metres), for the presentation.
func eye_drop() -> float:
	if fall == null:
		return 0.0
	var t := float(fall["t"])
	return minf(8.0 if fall["kind"] == "roof" else 3.2, t * t * 4.9)


func use_medkit() -> bool:
	if injury <= 0.0:
		_say("我：我没有受伤。")
		return false
	if treat != null:
		return true
	treat = {"t": 0.0}
	_say("我：我蹲下来包扎。（4 秒，别动）")
	return true


func near_clinic() -> bool:
	if String(_c.get("scene", "")) != CLINIC["room"] or not _rooms.has(CLINIC["room"]):
		return false
	var r: Dictionary = _rooms[CLINIC["room"]]
	var p := Vector2(float(r["ox"]) + float(CLINIC["c"]) * float(r["tw"]), float(r["oy"]) + float(CLINIC["r"]) * float(r["th"]))
	return Vector2(float(_c.get("x", 0.0)), float(_c.get("y", 0.0))).distance_to(p) < 1.3 * float(r["tw"])


## The clinic cabinet: one medkit a day. Returns true when handled.
func use_clinic() -> bool:
	if not near_clinic():
		return false
	var day := str(int(_c.get("day", 1)))
	if med_day.has(day):
		_say("我：药柜里今天的急救包已经拿过了。")
		return true
	_emit("give", {"id": "medkit", "day": day})
	return true


func gave_medkit(day: String) -> void:
	med_day[day] = true
	_say("我：药柜里有一个急救包。")


func tick(dt: float) -> void:
	if not (dt > 0.0) or bool(_c.get("dead", false)):
		return
	if fall != null:
		var f: Dictionary = fall
		var dur := FALL_ROOF if f["kind"] == "roof" else FALL_LINK
		f["t"] = float(f["t"]) + dt
		if float(f["t"]) >= dur:
			fall = null
			if f["kind"] == "roof":
				_emit("kill", {"msg": "手离开了栏杆。楼下的地面一下子近了。", "fx": "campus_fall", "source": "campus_fall", "back": f["from"]})
			else:
				_emit("land", {"room": f["room"], "side": int(f["side"])})
				hurt(LINK_INJURY, "fall")
				if injury < 100.0:
					_say("我：我摔在地上。腿一阵剧痛，还能走。")
					_emit("fact", {"what": "landed", "kind": "link"})
		return
	if treat != null:
		if bool(_c.get("moving", false)) or bool(_c.get("locked", false)):
			treat = null
			_say("我：包扎到一半被打断了。")
			return
		treat["t"] = float(treat["t"]) + dt
		if float(treat["t"]) >= MEDKIT_TIME:
			treat = null
			var before := injury
			injury = maxf(0.0, injury - MEDKIT)
			_emit("remove", {"id": "medkit"})
			_emit("fact", {"what": "treated", "from": before, "to": injury})
			_say("我：包扎好了。" + ("还疼，但能走了。" if injury >= 25.0 else "好多了。"))
		return
	if injury > 0.0 and injury < 25.0:
		var safe := not bool(_c.get("moving", false)) and not bool(_c.get("locked", false)) and not bool(_c.get("anomaly", false))
		rest_t = rest_t + dt if safe else 0.0
		if rest_t >= REST_AFTER:
			injury = maxf(0.0, injury - REST_RATE * dt)
