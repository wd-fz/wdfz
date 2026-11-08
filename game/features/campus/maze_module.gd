class_name MazeModule
extends FeatureModule
## The wrong elevator's space: elapsed pressure, safe respawn, two exits and ambient
## encounters. Geometry and rules use scene metres; adapters own movement, rendering and audio.

const ROOM := "lift_dream"
var geometry: MazeGeometry
var egg_cfg: Dictionary
var active := false
var elapsed := 0.0
var falls := 0
var respawning := false
var told_long := false
var sound_left := 20.0
var eggs: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []


func _init(shape: MazeGeometry, data: Dictionary) -> void:
	geometry = shape
	egg_cfg = data["eggs"].duplicate(true)
	reset()


func module_id() -> StringName:
	return &"campus.maze"


func state_version() -> int:
	return 1


func reset() -> void:
	active = false
	elapsed = 0.0
	falls = 0
	respawning = false
	told_long = false
	sound_left = 20.0
	_events.clear()
	_reset_eggs()
	_rng.randomize()


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func capture() -> Dictionary:
	return {"active": active, "elapsed": elapsed, "falls": falls, "told_long": told_long, "sound_left": sound_left,
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state)}


func validate(data: Dictionary) -> String:
	if not data.get("active") is bool or not data.get("told_long") is bool or not SaveSchema.number_in(data.get("elapsed"), 0.0, SaveSchema.MAX_SECONDS) \
		or not SaveSchema.is_integer(data.get("falls"), 0, 1000000) or not SaveSchema.number_in(data.get("sound_left"), 0.0, 60.0):
		return "特殊空间进度无效"
	if not String(data.get("rng_seed", "")).is_valid_int() or not String(data.get("rng_state", "")).is_valid_int():
		return "特殊空间随机状态无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	active = bool(data["active"])
	elapsed = float(data["elapsed"])
	falls = int(data["falls"])
	told_long = bool(data["told_long"])
	sound_left = float(data["sound_left"])
	_rng.seed = int(String(data["rng_seed"]))
	_rng.state = int(String(data["rng_state"]))


func enter(pose: Dictionary = {}, restoring: bool = false) -> Dictionary:
	active = true
	respawning = false
	if not restoring:
		elapsed = 0.0
		told_long = false
		_reset_eggs()
	if restoring and not pose.is_empty() and geometry.valid_ground_pose(pose):
		return pose.duplicate(true)
	return geometry.spawn(_rng)


func leave() -> void:
	active = false
	respawning = false
	elapsed = 0.0
	told_long = false
	_events.clear()
	_reset_eggs()


func take_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func _emit(kind: String, data: Dictionary = {}) -> void:
	data["kind"] = kind
	_events.append(data)


func drain_rate() -> float:
	return float(geometry.cfg["drainBase"]) + float(geometry.cfg["drainGrow"]) * elapsed


func step(dt: float, ctx: Dictionary) -> void:
	if not active or bool(ctx.get("dead", false)) or not is_finite(dt) or dt <= 0.0:
		return
	elapsed += dt
	_emit("san", {"amount": -drain_rate() * dt})
	_emit("settle", {"source": "void_lost", "fx": "void", "text": "黑暗里，我已经想不起自己是从哪扇门进来的。"})
	if not told_long and elapsed > 300.0:
		told_long = true
		_emit("notice", {"text": "我：在这里待得越久，越难想起外面是什么样子。得找到门。"})
	sound_left -= dt
	if sound_left <= 0.0:
		sound_left = 24.0 + _rng.randf() * 36.0
		var cues := ["steps", "knock", "door", "whisper"]
		_emit("sound", {"cue": "dread." + String(cues[_rng.randi_range(0, 3)]), "options": {"pan": _rng.randf_range(-1.0, 1.0), "k": _rng.randf_range(0.25, 0.55), "lp": 0.35}})
	var feet: Vector3 = ctx["feet"]
	if respawning:
		return # Pressure/ambience continue, but a pending fall can only be charged once.
	if feet.y < float(geometry.cfg["voidY"]):
		respawning = true
		falls += 1
		_emit("san", {"amount": -float(geometry.cfg["fallSan"])})
		_emit("settle", {"source": "void_fall", "fx": "abyss", "text": "我一直往下掉，掉到忘了自己是从哪里开始掉的。"})
		_emit("respawn")
		return
	_step_eggs(dt, ctx)


func finish_respawn() -> Dictionary:
	# The original chooses its random landing only at the black transition, not at the fall.
	if not active or not respawning:
		return {}
	respawning = false
	return {"pose":geometry.spawn(_rng), "text":"我：又回到了这里。四面还是那几堵白墙。" if falls>1 else "我：……我站在一开始的地方。身上没有伤，心跳得很快。"}


func nearby_exit(feet: Vector3, airborne: bool) -> Dictionary:
	if not active or airborne:
		return {}
	for door: Dictionary in geometry.cfg["exits"]:
		if absf(feet.y - float(door["h"])) < 1.2 and Vector2(feet.x - float(door["x"]), feet.z - float(door["z"])).length() < 1.7:
			return door
	return {}


func near_chalk(feet: Vector3, airborne: bool) -> bool:
	var spot: Dictionary = geometry.cfg["chalk"]
	return active and not airborne and absf(feet.y - float(spot["h"])) < 0.6 and Vector2(feet.x - float(spot["x"]), feet.z - float(spot["z"])).length() < 1.3


func hint(feet: Vector3, airborne: bool, has_chalk: bool) -> String:
	var door := nearby_exit(feet, airborne)
	if not door.is_empty():
		return "推开门（%s）" % door["name"]
	return "捡起粉笔" if near_chalk(feet, airborne) and not has_chalk else ""


func _reset_eggs() -> void:
	eggs = {"stare": 0.0, "invert": 0.0, "cool": 0.0, "seen": {}, "shadow": {}}


func _step_eggs(dt: float, ctx: Dictionary) -> void:
	var p: Vector3 = ctx["feet"]
	var ang := float(ctx.get("ang", 0.0))
	var inv: Dictionary = egg_cfg["invert"]
	if float(eggs["invert"]) > 0.0:
		eggs["invert"] = maxf(0.0, float(eggs["invert"]) - dt)
		if float(eggs["invert"]) == 0.0:
			_emit("invert_end")
	elif float(eggs["cool"]) > 0.0:
		eggs["cool"] = maxf(0.0, float(eggs["cool"]) - dt)
		eggs["stare"] = 0.0
	else:
		var pitch := float(ctx.get("pitch", 0.0))
		var void_gaze := false
		var target := Vector2.ZERO
		if not bool(ctx.get("moving", false)) and not bool(ctx.get("airborne", false)) and pitch <= float(inv["pitch"]):
			var distance := minf(float(inv["reach"]), float(ctx.get("eye", 1.65)) / tan(-pitch))
			target = Vector2(p.x, p.z) + Vector2(cos(ang), sin(ang)) * distance
			var floor_y := geometry.ground_at(target.x, target.y, p.y + float(geometry.cfg["step"]))
			void_gaze = not is_finite(floor_y) or floor_y < p.y - 1.5
		eggs["stare"] = float(eggs["stare"]) + dt if void_gaze else 0.0
		if float(eggs["stare"]) >= float(inv["stare"]):
			eggs["stare"] = 0.0
			eggs["invert"] = float(inv["dur"])
			eggs["cool"] = float(inv["cooldown"])
			_emit("invert", {"x": target.x, "z": target.y, "fy": p.y, "duration": inv["dur"]})
	var shadow: Dictionary = eggs["shadow"]
	if not shadow.is_empty():
		var spot := shadow_spot(String(shadow["id"]))
		shadow["time"] = float(shadow["time"]) + dt
		var to_shadow := Vector2(float(spot["x"]) - p.x, float(spot["z"]) - p.z)
		if CampusGeometry.ang_diff(to_shadow.angle(), ang) < 0.24 and to_shadow.length() < 20.0:
			shadow["look"] = float(shadow["look"]) + dt
		if float(shadow["look"]) >= float(spot["look"]) or (float(spot["near"]) > 0.0 and to_shadow.length() < float(spot["near"])) or float(shadow["time"]) >= float(spot["timeout"]):
			eggs["seen"][shadow["id"]] = true
			eggs["shadow"] = {}
			_emit("shadow_hide")
		return
	for spot: Dictionary in egg_cfg["shadows"]:
		if eggs["seen"].has(spot["id"]):
			continue
		var zone: Array = spot["zone"]
		if p.x < float(zone[0]) or p.x > float(zone[1]) or p.z < float(zone[2]) or p.z > float(zone[3]) or absf(p.y - float(zone[4])) > 0.6:
			continue
		var to_shadow := Vector2(float(spot["x"]) - p.x, float(spot["z"]) - p.z)
		if CampusGeometry.ang_diff(to_shadow.angle(), ang) > float(spot["view"]):
			continue
		eggs["shadow"] = {"id": spot["id"], "time": 0.0, "look": 0.0}
		_emit("shadow_show", spot.duplicate(true))
		return


func shadow_spot(id: String) -> Dictionary:
	for spot: Dictionary in egg_cfg["shadows"]:
		if spot["id"] == id:
			return spot
	return {}
