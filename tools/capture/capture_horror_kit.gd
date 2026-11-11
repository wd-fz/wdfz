extends SceneTree
## HorrorKit close-ups side by side (needs a display):
## godot --path . --script res://tools/capture/capture_horror_kit.gd [-- quality [kit|world|all]]
## Output: build/previews/horrorkit/hands.png (poses), hand-variants.png, heads.png, heads-dark.png (one cold key light),
## hand-close.png (palm up, claw, fist close-ups); with "world": the stall hand in the real teach1 toilet (dark, torch,
## close), the jump and turn-back smile, and the anomaly figures up close (stall-*.png, smile-*.png, figure-*.png).
## Positions, event state and elapsed time are injected; this is not a natural playthrough.

const APP := preload("res://game/app/app.tscn")

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
	var args := OS.get_cmdline_user_args()
	var q := int(args[0]) if not args.is_empty() else 4
	var mode := String(args[1]) if args.size() > 1 else "kit"
	if mode in ["kit", "all"]: await _kit(q)
	if mode in ["world", "all"]: await _world()
	quit()


func _kit(q: int) -> void:
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
	# Close-ups: palm up and curling, a claw, a fist (the finger joints and nails).
	_stage(.12)
	var close := [[.25, .35, [], Vector3(0, PI, PI)], [.2, .7, [null, [-.25, 1.3, 1.1], [-.25, 1.4, 1.2], [-.2, 1.3, 1.1], [-.1, 1.2, 1.0]], Vector3(0, PI, 0)], [1.0, .05, [], Vector3(0, PI, 0)]]
	for i in close.size():
		var h := HorrorKit.hand({"quality": q, "long": 1.2, "thin": .35})
		HorrorKit.pose_hand(h, close[i][0], close[i][1], close[i][2])
		h.position = Vector3((i - 1) * .2, 0, 0)
		h.rotation = close[i][3]
		world.add_child(h)
	_aim(cam, Vector3(0, .3, .42), Vector3(0, 0, .08))
	_aim(key, Vector3(-.5, .9, .7), Vector3(0, 0, .05))
	key.light_energy = 1.4
	await _shot("hand-close")
	# Heads with hair and a bust, a little turned, under a low key: an ordinary student, but wrong.
	_stage(.03, false)
	var busts := [{"hair": true}, {"hair": true, "mouth": "wide", "open": .8, "skew": .6}, {"mouth": "none", "eyes": "hollow", "hair": true}]
	for i in busts.size():
		var opts: Dictionary = busts[i]
		opts["quality"] = q
		var hd := HorrorKit.bust(opts)
		hd.position = Vector3((i - 1) * .26, 0, 0)
		hd.rotation.y = [.5, 0.0, -.5][i]
		world.add_child(hd)
	_aim(cam, Vector3(0, -.03, -1.1), Vector3(0, -.06, 0))
	_aim(key, Vector3(-.8, .5, -.9), Vector3(0, 0, 0))
	key.light_energy = 1.2
	key.spot_angle = 30
	await _shot("heads-profile")
	# The anomaly figures in a plain lit room (the neck one is 4 m tall, so it cannot stand in a corridor): whole, then the heads.
	_stage(.3)
	var twin := AnomalyProps.new()
	var necker := AnomalyProps.new()
	world.add_child(twin)
	world.add_child(necker)
	twin.build("twin", {}, null, Vector3(-1.3, 0, 0), Vector2.RIGHT, q)
	necker.build("necker", {}, null, Vector3(1.3, 0, 0), Vector2.RIGHT, q)
	for props: AnomalyProps in [twin, necker]:
		props.position = Vector3.ZERO
		props.items[0].rotation = Vector3.ZERO
	twin.items[0].position = Vector3(-1.3, 0, 0)
	necker.items[0].position = Vector3(1.3, 0, 0)
	_aim(key, Vector3(-3, 4.5, 9), Vector3(0, 1.8, 0))
	key.light_energy = 14.0
	key.spot_angle = 60
	key.spot_range = 30
	_aim(cam, Vector3(0, 2.0, 9.5), Vector3(0, 1.9, 0))
	cam.fov = 52
	await _shot("figure-necker")
	_aim(cam, Vector3(-1.3, 2.35, 2.3), Vector3(-1.3, 2.25, 0))
	cam.fov = 36
	await _shot("figs-heads")
	_aim(cam, Vector3(1.3, 3.6, 3.0), Vector3(1.3, 3.2, 0))
	await _shot("figs-necker-head")
	world.free()
	world = null


## The real game: the stall hand in teach1's toilet, the smiles and the anomaly figures.
func _world() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://capture-horror-kit/save.json")
	app.settings = GameSettings.new("user://capture-horror-kit/settings.json")
	root.add_child(app)
	await process_frame
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard", "none")
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app._stand_up()
	app.patrol().pat["safety"] = 999.0
	var room := CampusData.layout("teach1")
	# Standing in the toilet (tiles 58..61 x 16..19), facing the stalls (row 16); the hand comes 8 units ahead.
	var me := CampusGeometry.tile_center(room, 58, 18) + Vector2(1, 2.5)
	var ang := -PI / 2 + .1
	var src := me + Vector2(cos(ang), sin(ang)) * 8.0
	for night in [false, true]:
		app.school().tsec = 1500 if night else 720
		for setup in [["stand", 0.0, -1.0, false], ["torch", 0.0, -1.0, true], ["close", 5.5, -1.3, false], ["crouch", -1.0, -.62, true]]:
			var at := CampusGeometry.to_scene(room, me + Vector2(cos(ang), sin(ang)) * float(setup[1]))
			if app.session.world_id != "teach1": app.travel("teach1", {"position": [at.x, 0, at.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": setup[2]}, false)
			app.player.restore_pose({"position": [at.x, 0, at.y], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": setup[2]})
			var eye_y := app.player.camera.position.y
			if setup[0] == "crouch": app.player.camera.position.y = .55
			var cw := app._campus_world()
			cw.anomaly_fx.visual_seed = 42
			var data := {"src": {"x": src.x, "y": src.y}, "chosen": null, "scene": "teach1"}
			app.anomaly().an.merge({"id": "hand", "active": true, "t": 2.0, "acc": 0.0, "data": data}, true)
			for frame in 150:
				cw.anomaly_fx.update(1.0 / 60, app.anomaly().an, room, "teach1", app.player.position, Vector2.from_angle(ang))
			if setup[3] and not app.items().has("torch"): app.items().add("torch")
			app.items().torch_on = setup[3]
			app.player.camera.get_node("Torch").visible = setup[3]
			cw.lighting.update(0, app.school().tsec, app.player.camera)
			app._school_step(0, app.campus())
			app.ui.show_notice("")
			app.ui.show_prompt("")
			await _shot_n("stall-%s%s" % ["night-" if night else "", setup[0]], 10)
			app.player.camera.position.y = eye_y
			app.anomaly().end_now()
	# The smiles: in your face (0.1 s, 0.3 s, 1.0 s) and behind you (turned, 0.4 s, 1.5 s), in the dark corridor.
	app.school().tsec = 1500
	var corridor := CampusGeometry.to_scene(room, CampusGeometry.tile_center(room, 30, 19))
	app.travel("teach1", {"position": [corridor.x, 0, corridor.y], "yaw": CampusGeometry.yaw_from_ang(0), "pitch": 0.0}, false)
	var cw2 := app._campus_world()
	cw2.lighting.update(0, app.school().tsec, app.player.camera)
	for spec in [["jump", .1], ["jump", .3], ["jump", 1.0], ["behind", .4], ["behind", 1.5]]:
		var cam_pos := app.player.camera.global_position
		cw2.phantoms.show_smile(spec[0], cam_pos, CampusGeometry.ang_from_yaw(app.player.rotation.y))
		var steps := int(float(spec[1]) * 60)
		for _i in steps: cw2.phantoms.tick_smile(1.0 / 60, cam_pos)
		app.ui.show_prompt("")
		await _shot_n("smile-%s-%.1f" % spec, 2)
		cw2.phantoms.clear_smile()
	# The anomaly figures up close (twin, repeat), 3.2 m ahead in the dark corridor, torch on them.
	for kind in ["twin", "repeat"]:
		var props := AnomalyProps.new()
		cw2.add_child(props)
		var ahead := Vector3(cos(0.0), 0, sin(0.0))
		var here := app.player.camera.global_position
		var at := Vector3(here.x + ahead.x * 3.2, 0, here.z + ahead.z * 3.2)
		props.build(kind, {}, null, at, Vector2.RIGHT, 4)
		props.items[0].rotation.y = atan2(here.x - props.items[0].position.x, here.z - props.items[0].position.z)
		app.ui.show_prompt("")
		await _shot_n("figure-%s" % kind, 3)
		props.queue_free()
	app.return_to_menu()
	app.queue_free()
	await process_frame


func _shot_n(name: String, frames: int) -> void:
	for _i in frames: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/horrorkit/%s.png" % name)
	print("CAPTURED: " + name)
