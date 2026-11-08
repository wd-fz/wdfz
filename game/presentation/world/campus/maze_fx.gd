class_name MazeFx
extends Node3D
## The maze's quiet encounters; no gameplay mutations. Cleared at every scene/session boundary.

var player: PlayerController
var audio: AudioFx
var screen: MazeScreen
var shadow: Node3D
var abyss: Node3D
var _shadow_alpha := 0.0
var _shadow_out := false
var _invert_on := false
var _invert_k := 0.0
var _fade := 0.0


func setup(owner_player: PlayerController, owner_audio: AudioFx) -> void:
	player = owner_player
	audio = owner_audio
	screen = MazeScreen.new()
	add_child(screen)


static func _figure(color: Color, size: float) -> Node3D:
	var root := FigureModel.make("tall", color)
	root.scale = Vector3.ONE * size
	for mesh: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.disable_fog = color.r > 0.5
		(mesh as MeshInstance3D).material_override = mat
	return root


func _pan(spot: Vector3) -> float:
	var relative := atan2(spot.z - player.position.z, spot.x - player.position.x) - CampusGeometry.ang_from_yaw(player.rotation.y)
	return sin(relative) * 0.85


func event(ev: Dictionary) -> void:
	match ev["kind"]:
		"invert":
			if is_instance_valid(abyss):
				abyss.queue_free()
			abyss = _figure(Color.WHITE, 1.6)
			add_child(abyss)
			var pitch := minf(-0.5, float(player.capture_pose()["pitch"]))
			var ang := CampusGeometry.ang_from_yaw(player.rotation.y)
			abyss.position = player.position + Vector3(cos(ang) * cos(pitch) * 9.0, player.camera.position.y + sin(pitch) * 9.0 - 2.1, sin(ang) * cos(pitch) * 9.0)
			abyss.rotation.y = PI + atan2(player.position.x - abyss.position.x, player.position.z - abyss.position.z)
			_invert_on = true
			audio.duck(float(ev["duration"]) + 0.35)
			audio.play("void.thud")
		"invert_end":
			_invert_on = false
			if is_instance_valid(abyss):
				abyss.queue_free()
			abyss = null
		"shadow_show":
			if is_instance_valid(shadow):
				shadow.queue_free()
			shadow = _figure(Color(0, 0, 0, 0), 1.05)
			add_child(shadow)
			shadow.position = Vector3(float(ev["x"]), float(ev["h"]), float(ev["z"]))
			shadow.rotation.y = -PI / 2.0 - float(ev["face"])
			_shadow_alpha = 0.0
			_shadow_out = false
			audio.play("dread." + String(ev.get("cue", "steps")), {"pan": _pan(shadow.position), "k": 0.32})
		"shadow_hide":
			_shadow_out = true
			if is_instance_valid(shadow):
				audio.play("void.gust", {"pan": _pan(shadow.position)})


func fall_fade() -> void:
	_fade = 1.0


func advance(dt: float, soft: bool) -> void:
	_invert_k = move_toward(_invert_k, (0.8 if soft else 1.0) if _invert_on else 0.0, dt / ((0.18 if soft else 0.05) if _invert_on else (0.45 if soft else 0.25)))
	_fade = maxf(0.0, _fade - dt * 2.0)
	screen.show_effect(_invert_k, -0.2, 0.0, -0.22, _fade)
	if is_instance_valid(shadow):
		_shadow_alpha = move_toward(_shadow_alpha, 0.0 if _shadow_out else 1.0, dt / (0.35 if _shadow_out else 0.5))
		for mesh: Node in shadow.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override.albedo_color.a = _shadow_alpha
		if _shadow_out and _shadow_alpha <= 0.0:
			shadow.queue_free()
			shadow = null


func clear_effects() -> void:
	if is_instance_valid(screen):
		screen.show_effect()
	for node: Node in [shadow, abyss]:
		if is_instance_valid(node):
			node.queue_free()
	shadow = null
	abyss = null
	_invert_on = false
	_invert_k = 0.0
