extends SceneTree
## The dressed figures of the death stages (tools/remodel/dress.py) as DeathShots._fig builds them: matte
## cloth per garment, HorrorKit head. Needs a display:
## godot --path . --script res://tools/capture/capture_dressed.gd
## Output: build/previews/dressed/row.png (person, sit, teacher, roam under one cold key light),
## close.png (person, chest up), sit.png (the seated pupil, three-quarter), lit.png (person in a brighter light).

var world: Node3D
var cam: Camera3D
var key: SpotLight3D
var shots: DeathShots


func _initialize() -> void:
	call_deferred("_run")


func _stage(energy: float, ambient: float) -> void:
	if world != null: world.free()
	world = Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.03, .035, .04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.5, .55, .6)
	env.environment.ambient_light_energy = ambient
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	key = SpotLight3D.new()
	key.light_color = Color(.85, .88, .9)
	key.light_energy = energy
	key.spot_range = 14
	key.spot_angle = 40
	world.add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(.12, .13, .12)
	floor_mesh.material_override = floor_mat
	world.add_child(floor_mesh)
	cam = Camera3D.new()
	cam.fov = 34
	world.add_child(cam)
	shots = DeathShots.new(null)
	shots.root = Node3D.new()
	world.add_child(shots.root)


func _aim(n: Node3D, from: Vector3, at: Vector3) -> void:
	n.position = from
	n.basis = Basis.looking_at(at - from, Vector3.UP)


func _shot(name: String) -> void:
	for _i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/previews/dressed/%s.png" % name)
	print("CAPTURED: " + name)


func _people(tone: Color) -> void:
	var at := {"person": -1.5, "sit": -.5, "teacher": .55, "roam": 1.6}
	for kind: String in at:
		var actor := shots._fig(Vector3(at[kind], 0, 0), kind, 1.85 / FigureModel.height(kind) if kind != "sit" else 1.0, tone, {"tone": DeathShots.SKIN, "mouth": "closed", "skew": .2, "hair": true}, .3)
		actor.rotation.y = PI + (.35 if kind == "sit" else 0.0)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://build/previews/dressed")
	_stage(5.0, .35)
	_people(Color("11141a"))
	_aim(key, Vector3(1.2, 3.2, -3.0), Vector3(0, 1.0, 0))
	_aim(cam, Vector3(0, 1.1, -6.2), Vector3(0, .95, 0))
	await _shot("row")
	_aim(cam, Vector3(-1.35, 1.55, -1.25), Vector3(-1.5, 1.35, 0))
	await _shot("close")
	_aim(cam, Vector3(-.1, 1.15, -1.6), Vector3(-.5, .8, 0))
	await _shot("sit")
	_stage(12.0, .6)
	_people(Color("11141a"))
	_aim(key, Vector3(-1.0, 2.6, -2.4), Vector3(-1.5, 1.2, 0))
	_aim(cam, Vector3(-1.2, 1.3, -2.3), Vector3(-1.5, 1.1, 0))
	await _shot("lit")
	world.free()
	DeathShots.clear_cache()
	HorrorKit.clear_cache()
	quit()
