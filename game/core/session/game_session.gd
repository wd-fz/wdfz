class_name GameSession
extends RefCounted
## One owner per run. App composes adapters; scenes never reach into this state.

signal notice_requested(text: String)

var clock := RunClock.new()
var modules := ModuleHost.new()
var world_id := ""
var running := false


func start(location: String) -> void:
	clock = RunClock.new()
	modules.reset()
	world_id = location
	running = true


func advance(delta: float, calendar_running: bool = true) -> void:
	if not running or not is_finite(delta) or delta <= 0.0:
		return
	clock.advance(delta, calendar_running)
	modules.advance(delta)


func interact(id: StringName) -> void:
	if running:
		notice_requested.emit(modules.interact(id))


func capture(player_pose: Dictionary) -> Dictionary:
	return {
		"format": SaveSchema.FORMAT,
		"version": SaveSchema.VERSION,
		"world_id": world_id,
		"clock": clock.capture(),
		"player": player_pose.duplicate(true),
		"modules": modules.capture(),
	}


func validate(data: Dictionary, known_worlds: PackedStringArray) -> String:
	var error := SaveSchema.validate(data, known_worlds)
	if not error.is_empty():
		return error
	return modules.validate(data["modules"])


func restore(data: Dictionary) -> void:
	# Restore state, not commands: never replay rewards or interaction callbacks.
	clock = RunClock.new()
	clock.restore(data["clock"])
	modules.restore(data["modules"])
	world_id = data["world_id"]
	running = true


func stop() -> void:
	if running:
		modules.stop()
	running = false
