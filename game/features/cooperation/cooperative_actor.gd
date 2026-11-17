class_name CooperativeActor
extends RefCounted
## One personal rule session and pose. No device input, rendering, or transport.
const RUNTIME_FIELDS := {
	"phone.network": ["connection"], "story.paper_plane": ["s"], "story.window_gaze": ["s"], "campus.tales": ["_pending"], "dlc.campus_rules": ["_pending", "_knock_elapsed", "records"], "school.days": ["lesson_key"], "body.injury": ["fall", "treat"],
	"campus.facilities": ["_pending"], "story.routes": ["_pending"], "garage.world": ["_pending"],
	"story.broadcast": ["_pending"], "story.exchange": ["_pending"], "story.investigation": ["_pending"],
	"school.classmates": ["state"], "campus.marks": ["_pending"],
}
var id := ""
var session: GameSession
var pose := {"position": [0.0, 0.05, 0.0], "yaw": 0.0, "pitch": 0.0}
var scene_version := 1
var input_sequence := -1
var processed_sequence := -1
var command_sequence := -1
var input_age := 0.0
var input := {"x": 0.0, "y": 0.0, "yaw": 0.0, "pitch": 0.0, "run": false}
var moving := false
var running := false
var choice: Dictionary = {}
var terminal := false
var mic := false
var phone_uid := ""
var tunnel_return: Dictionary = {}
var special_return: Dictionary = {}
var hidden_history: Dictionary = {}
var locker := LockerOverstay.new()
var activities := CooperativeActivities.new()
var vehicle := false
var own_seat := ""
var events: Array = []
var event_sequence := 0
var enter_cool := 0.0
var death_elapsed := 0.0
var leases: Array = []
var pending: Array = []


func feature(key: StringName) -> FeatureModule:
	return session.modules.get_module(key)


func school() -> SchoolModule:
	return feature(&"school.day") as SchoolModule


func bag() -> InventoryModule:
	return feature(&"items.bag") as InventoryModule


func fate() -> StoryModule:
	return feature(&"story.death") as StoryModule


func talent() -> TalentModule:
	return feature(&"story.talent") as TalentModule


func watcher() -> PatrolModule:
	return feature(&"patrol.world") as PatrolModule


func location() -> String:
	return session.world_id


func point(rooms: Dictionary) -> Vector2:
	var p: Array = pose["position"]
	return CampusGeometry.to_world(rooms.get(location()), float(p[0]), float(p[2]))


func event(kind: String, data: Dictionary = {}) -> void:
	event_sequence += 1
	var e := data.duplicate(true)
	e["kind"] = kind
	e["seq"] = event_sequence
	events.append(e)
	while events.size() > 64: events.pop_front()


func clear_input() -> void:
	input["x"] = 0.0
	input["y"] = 0.0
	input["run"] = false
	input["vault"] = false
	input["steer"] = {}
	moving = false
	running = false


func accept_input(data: Dictionary) -> bool:
	if int(data.get("scene", -1)) != scene_version or int(data.get("seq", -1)) <= input_sequence: return false
	input_sequence = int(data["seq"])
	input_age = 0.0
	input = {"x": float(data["x"]), "y": float(data["y"]), "yaw": float(data["yaw"]), "pitch": float(data["pitch"]), "run": bool(data["run"]), "vault": bool(data.get("vault", false)), "steer": data.get("steer", {}).duplicate()}
	return true


func travel(world: String, at: Dictionary) -> void:
	session.world_id = world
	pose = at.duplicate(true)
	scene_version += 1
	input["yaw"] = pose["yaw"]
	input["pitch"] = pose["pitch"]
	clear_input()
	bag().cancel_search()
	choice.clear()
	terminal = false
	enter_cool = 1.0


func capture() -> Dictionary:
	var runtime := {}
	for key: String in RUNTIME_FIELDS:
		var m := feature(StringName(key))
		var extra := {}
		for property: String in RUNTIME_FIELDS[key]: extra[property] = m.get(property)
		if not extra.is_empty(): runtime[String(key)] = extra
	return {"session": session.capture(pose), "scene": scene_version, "seat": own_seat, "input_seq": input_sequence, "command_seq": command_sequence,
		"life": {"dead": fate().dead, "ended": fate().ended, "fx": fate().death_fx, "msg": fate().death_msg, "source": fate().death_source, "wake": fate().wake_pending, "elapsed": death_elapsed},
		"choice": choice.duplicate(true), "terminal": terminal, "mic": mic, "activities": activities.capture(), "phone_uid": phone_uid, "special_return": special_return.duplicate(true), "hidden_history": hidden_history.duplicate(), "tunnel_return": tunnel_return.duplicate(true), "locker": {"t": locker.t, "stage": locker.stage}, "vehicle": vehicle, "events": events.duplicate(true), "event_seq": event_sequence,
		"search": bag()._job.duplicate(true), "pending": pending.duplicate(true), "runtime": runtime.duplicate(true)}


func restore(data: Dictionary) -> void:
	session.restore(data["session"])
	pose = data["session"]["player"].duplicate(true)
	own_seat = String(data["seat"])
	school().assign_own_seat(own_seat)
	scene_version = int(data["scene"]) + 1
	var life: Dictionary = data["life"]
	fate().dead = bool(life["dead"])
	fate().ended = String(life["ended"])
	fate().death_fx = String(life["fx"])
	fate().death_msg = String(life["msg"])
	fate().death_source = String(life["source"])
	fate().wake_pending = bool(life["wake"])
	death_elapsed = float(life["elapsed"])
	choice = data.get("choice", {}).duplicate(true)
	terminal = bool(data.get("terminal", false))
	mic = bool(data.get("mic", false))
	activities.restore(data.get("activities", {}))
	phone_uid = String(data.get("phone_uid", ""))
	special_return = data.get("special_return", {}).duplicate(true)
	hidden_history = data.get("hidden_history", {}).duplicate()
	tunnel_return = data.get("tunnel_return", {}).duplicate(true)
	locker.t = float(data.get("locker", {}).get("t", 0))
	locker.stage = int(data.get("locker", {}).get("stage", 0))
	vehicle = bool(data.get("vehicle", false))
	events = data.get("events", []).duplicate(true)
	event_sequence = int(data.get("event_seq", 0))
	bag()._job = data.get("search", {}).duplicate(true)
	pending = data.get("pending", []).duplicate(true)
	for key: String in data.get("runtime", {}):
		var m := feature(StringName(key))
		for property: String in data["runtime"][key]: m.set(property, data["runtime"][key][property])
	(feature(&"phone.network") as PhoneModule).terminal_open = terminal
	input["yaw"] = pose["yaw"]
	input["pitch"] = pose["pitch"]
	clear_input()
