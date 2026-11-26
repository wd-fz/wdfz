class_name StudentAvatar
extends Node3D
## The lobby and both game views use the same skinned asset and in-place clips.
const LOCOMOTION := ["idle", "walk", "run", "back", "left", "right", "turn_left", "turn_right", "limp"]
var character := ""
var animation: AnimationPlayer
var skeleton: Skeleton3D
var clip := ""
var _goal := ""
var _model: Node3D
var _props := {}
var _bones := {}
var _upper_tracks := {}
var _upper_action := ""
var _upper_time := 0.0


func dress(id: String) -> void:
	id = StudentCast.resolve(id)
	_load_actor(id, float(StudentCast.PEOPLE[id]["height"]))


func dress_teacher() -> void:
	_load_actor("teacher", 1.04)


func _load_actor(id: String, height: float) -> void:
	if id == character: return
	if _model != null:
		remove_child(_model)
		_model.queue_free()
	_props.clear()
	_bones.clear()
	_upper_tracks.clear()
	_upper_action = ""
	character = id
	animation = null
	skeleton = null
	var scene := CampusData.actor_scene("res://assets/characters/%s.glb" % id)
	_model = scene.instantiate() as Node3D if scene != null else null
	if _model == null: return
	for part: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		RenderMaterials.apply_character_palette(part.mesh)
	add_child(_model)
	_model.scale = Vector3.ONE * height
	animation = _model.get_node_or_null("AnimationPlayer")
	var rigs := _model.find_children("*", "Skeleton3D", true, false)
	if animation == null or rigs.is_empty():
		CampusEntryLog.resource_issue("人物缺少动画或骨架 · " + id)
		animation = null
		return
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton = rigs[0]
	for i in skeleton.get_bone_count(): _bones[skeleton.get_bone_name(i)] = i
	_goal = ""
	clip = ""


static func locomotion(local_motion: Vector3, moving: bool, running: bool, turning: float = 0.0) -> String:
	if not moving:
		if absf(turning) > 0.55: return "turn_left" if turning > 0.0 else "turn_right"
		return "idle"
	if absf(local_motion.x) > absf(local_motion.z) * 1.25: return "right" if local_motion.x > 0 else "left"
	if local_motion.z > 0.015: return "back"
	return "run" if running else "walk"


func advance(action: String, dt: float, pace: float = 1.0, gear: int = 0, pitch: float = 0.0, upper_action: String = "") -> void:
	if animation == null: return
	if action == "idle" and gear & 1: action = "torch"
	if action != _goal:
		var next := action
		if action == "sit" and not _goal.is_empty() and _goal != "ride": next = "sit_down"
		elif _goal == "sit" and (action in LOCOMOTION or action == "torch"): next = "stand_up"
		elif action == "down" and not _goal.is_empty(): next = "collapse"
		_goal = action
		_play(next)
	animation.speed_scale = clampf(pace, 0.52, 1.8) if clip in LOCOMOTION and clip != "idle" else 1.0
	animation.advance(dt)
	if clip != _goal and not animation.is_playing(): _play(_goal)
	if upper_action != _upper_action:
		_upper_time = 0
		_upper_action = upper_action
	if upper_action != "": _upper_body(upper_action, dt)
	# The runtime look offsets the baked head pose. The animation samples it
	# anew on every advance, including a zero-delta initial placement.
	var head := skeleton.find_bone(&"Head")
	if head < 0: return
	var aim := Quaternion(Vector3.RIGHT, clampf(pitch * .64, -.65, .65))
	skeleton.set_bone_pose_rotation(head, skeleton.get_bone_pose_rotation(head) * aim)
	if gear != 0 or not _props.is_empty(): _equipment(gear)


func _play(action: String) -> void:
	var blend := 0.13 if not clip.is_empty() else 0.0
	clip = action
	animation.play(action, blend)
	animation.advance(0.0)


## Preserve the feet's walk or seat pose while a hand operates a door, book or terminal.
func _upper_body(action: String, dt: float) -> void:
	var take := animation.get_animation(action)
	if take == null: return
	if not _upper_tracks.has(action):
		var tracks := {}
		for i in take.get_track_count():
			if take.track_get_type(i) != Animation.TYPE_ROTATION_3D: continue
			var path := take.track_get_path(i)
			if path.get_subname_count() != 1: continue
			var bone := path.get_subname(0)
			if bone in [&"Chest",&"Head",&"ArmL",&"ArmR",&"ElbowL",&"ElbowR",&"HandL",&"HandR"]:
				tracks[i] = _bones[bone]
		_upper_tracks[action] = tracks
	_upper_time += dt
	var at := minf(_upper_time,take.length) if take.loop_mode == Animation.LOOP_NONE else fmod(_upper_time,take.length)
	var weight := minf(_upper_time/.1,1.0)
	for t: int in _upper_tracks[action]:
		var b: int = _upper_tracks[action][t]
		var target := take.rotation_track_interpolate(t,at)
		skeleton.set_bone_pose_rotation(b,skeleton.get_bone_pose_rotation(b).slerp(target,weight))


func _equipment(mask: int) -> void:
	for bit: int in [1, 2, 4]:
		var on := (mask & bit) != 0
		var side := "L" if bit == 2 or (bit == 4 and not mask & 2) else "R"
		if on and not _props.has(bit):
			var mount := BoneAttachment3D.new()
			mount.bone_name = "Hand" + side
			skeleton.add_child(mount)
			mount.add_child(_prop(bit))
			_props[bit] = mount
		if not _props.has(bit): continue
		var attachment: BoneAttachment3D = _props[bit]
		attachment.visible = on
		if not on: continue
		if attachment.bone_name != "Hand" + side: attachment.bone_name = "Hand" + side
		if _goal in LOCOMOTION or _goal == "sit" or (_goal == "torch" and bit != 1):
			var bend := 1.5 if bit == 4 else 1.25 if bit == 2 else 0.50
			skeleton.set_bone_pose_rotation(_bones["Arm"+side], Quaternion(Vector3.RIGHT, 0.55))
			skeleton.set_bone_pose_rotation(_bones["Elbow"+side], Quaternion(Vector3.RIGHT, bend))
		if bit == 2:
			var umbrella: Node3D = attachment.get_child(0)
			umbrella.basis = skeleton.get_bone_global_pose(_bones[attachment.bone_name]).basis.inverse()


static func _prop(bit: int) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.76
	if bit == 4:
		var phone := BoxMesh.new()
		phone.size = Vector3(.067, .132, .009)
		mesh.mesh = phone
		mat.albedo_color = Color("426077")
		mesh.rotation.x = .35
	elif bit == 1:
		var torch := CylinderMesh.new()
		torch.top_radius = .032
		torch.bottom_radius = .021
		torch.height = .165
		torch.radial_segments = 12
		mesh.mesh = torch
		mat.albedo_color = Color("687680")
	else:
		var shaft := CylinderMesh.new()
		shaft.top_radius = .006
		shaft.bottom_radius = .006
		shaft.height = .57
		shaft.radial_segments = 8
		mesh.mesh = shaft
		mesh.position.y = .22
		mat.albedo_color = Color("9caba8")
		var canopy := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = .44
		dome.height = .32
		dome.is_hemisphere = true
		dome.radial_segments = 12
		dome.rings = 5
		canopy.mesh = dome
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color("42677b")
		cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
		canopy.material_override = cloth
		canopy.position.y = .50
		root.add_child(canopy)
	mesh.material_override = mat
	root.add_child(mesh)
	root.position = Vector3(0, -.045, -.018)
	return root
