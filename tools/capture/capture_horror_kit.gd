extends SceneTree
## HorrorKit close-ups side by side (needs a display):
## godot --path . --script res://tools/capture/capture_horror_kit.gd [-- quality]
## Output: build/previews/horrorkit/hands.png (poses), hand-variants.png, heads.png, heads-dark.png (one cold key light).

var world: Node3D
var cam: Camera3D
var key: SpotLight3D


func _initialize() -> void:
	call_deferred("_run")


func _stage(ambient: float, ground: bool = true) -> void:
	if world != null: world.free()
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.02, .025, .03)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.5, .58, .62)
	env.environment.ambient_light_energy = ambient
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(env)
	key = SpotLight3D.new()
	key.light_color = Color(.8, .88, .92)
	key.spot_range = 12
	key.spot_angle = 50
	world.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(.09, .1, .1)
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -.035
	if ground: world.add_child(floor_mesh)
	else: floor_mesh.free()
	cam = Camera3D.new()
	cam.fov = 36
	world.add_child(cam)


func _aim(n: Node3D, from: Vector3, at: Vector3) -> void:
	n.position = from
	n.basis = Basis.looking_at(at - from, Vector3.UP)


func _shot(name: String) -> void:
	for _i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/horrorkit/%s.png" % name)
	print("CAPTURED: " + name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/horrorkit")
	var q := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 4
	# Hands: relaxed, splayed, claw, curled, palm up beckoning.
	_stage(.25)
	var poses := [[.15, .2, []], [-.12, 1.0, []], [.2, .7, [null, [-.25, 1.3, 1.1], [-.25, 1.4, 1.2], [-.2, 1.3, 1.1], [-.1, 1.2, 1.0]]], [.95, .1, []], [.4, .3, [.1]]]
	for i in poses.size():
		var h := HorrorKit.hand({"quality": q})
		HorrorKit.pose_hand(h, poses[i][0], poses[i][1], poses[i][2])
		h.position = Vector3((i - 2) * .22, 0, 0)
		h.rotation = Vector3(0, PI, PI if i == 4 else 0.0)
		world.add_child(h)
	_aim(cam, Vector3(0, .42, .62), Vector3(0, 0, .06))
	_aim(key, Vector3(-.5, .9, .7), Vector3(0, 0, .05))
	key.light_energy = 1.6
	await _shot("hands")
	# Variants: too long, an extra joint, bony, a shadow hand.
	_stage(.25)
	var variants := [{}, {"long": 1.35}, {"extra": true}, {"thin": 1.0, "long": 1.2}, {"tone": "shadow"}]
	for i in variants.size():
		var opts: Dictionary = variants[i]
		opts["quality"] = q
		var h := HorrorKit.hand(opts)
		HorrorKit.pose_hand(h, .3, .45)
		h.position = Vector3((i - 2) * .22, 0, 0)
		h.rotation.y = PI
		world.add_child(h)
	_aim(cam, Vector3(0, .42, .62), Vector3(0, 0, .06))
	_aim(key, Vector3(-.5, .9, .7), Vector3(0, 0, .05))
	key.light_energy = 1.6
	await _shot("hand-variants")
	# Heads: closed, no mouth, wide and open, skewed eyes, long neck, shadow.
	for dark in [false, true]:
		_stage(.02 if dark else .25, false)
		var heads := [{}, {"mouth": "none", "eyes": "hollow"}, {"mouth": "wide", "open": .7}, {"skew": 1.0, "open": .35}, {"neck": .25, "open": .15}, {"tone": "shadow", "open": .5}]
		for i in heads.size():
			var opts: Dictionary = heads[i]
			opts["quality"] = q
			var hd := HorrorKit.head(opts)
			hd.position = Vector3((i - 2.5) * .19, .02 if i == 4 else 0.0, 0)
			hd.rotation.y = .25 * (i % 2 * 2 - 1) * (1 if dark else 0)
			world.add_child(hd)
		_aim(cam, Vector3(0, .03, -.95), Vector3(0, -.01, 0))
		_aim(key, Vector3(-.6, .9, -1.1) if not dark else Vector3(-1.1, .55, -.45), Vector3(0, 0, 0))
		key.light_energy = 1.6 if not dark else 1.0
		key.spot_angle = 50 if not dark else 22
		await _shot("heads-dark" if dark else "heads")
	world.free()
	quit()
