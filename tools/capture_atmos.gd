extends SceneTree
## Global atmosphere (needs a display): godot --path . --script res://tools/capture_atmos.gd
## Output: build/previews/atmos/. Day 3, early evening: the dead stretch and emergency sign of a
## corridor, the mop and bucket facing you, a figure at the window. (A class turning cannot be seen
## on the symmetric placeholder capsules; it is covered by the rule tests.)

const APP := preload("res://scenes/app.tscn")
const OUT := "res://build/previews/atmos/"


func _initialize() -> void:
	call_deferred("_run")


func _look(app: GameApp, from: Vector3, at: Vector3, pitch: float = 0.0) -> void:
	app.player.global_position = Vector3(from.x, 0.05, from.z)
	app.player.rotation.y = atan2(-(at.x - from.x), -(at.z - from.z))
	app.player.camera.rotation.x = pitch


func _shot(app: GameApp, name: String) -> void:
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new("user://atmos-preview/unused.json")
	root.add_child(app)
	await process_frame
	app.start_new_game()
	app.patrol().pat["safety"] = 999.0
	app._stand_up()
	app.school().day = 3
	app.school().tsec = 17.0 * 60.0 + 10.0
	DirAccess.make_dir_recursive_absolute(OUT)
	var t1 := CampusData.layout("teach1")
	# The corridor of floor 1.
	var door := AtmosFx.last_door_row(t1)
	var fx: AtmosFx = app._campus_world().atmos_fx
	var sign_at := fx.signs[0].global_position
	var mop := fx.props.global_position
	print("sign ", sign_at, " mop ", mop)
	_look(app, Vector3(mop.x + 4.0, 0.05, mop.z + 2.8), sign_at + Vector3(0, -0.3, 0), 0.1)
	await _shot(app, "corridor-dark-stretch")
	# The mop and bucket, shifted to face the player.
	fx.apply_shift("face", {"angle": 0.0})
	_look(app, Vector3(mop.x + 3.0, 0.05, mop.z + 3.0), mop + Vector3(0, 0.4, 0), -0.1)
	app.player.rotation.y = atan2(-(mop.x - (mop.x + 3.0)), -(mop.z - (mop.z + 3.0)))
	await _shot(app, "mop-faces-you")
	print("door row ", door, " signs ", fx.signs.size(), " dark lamps ", app._campus_world().lighting.lamp_dark.size(), "/", app._campus_world().lighting.room_lights.size())
	app.travel("teach1", app.campus().default_spawn("teach1"), false)
	# A figure at the frosted window.
	app.atmos().stare = {}
	app.atmos().window = {"room": "teach1", "cls": "teach1:0", "seed": 0.5, "seen": 0.0, "gone": false}
	var wn := CampusGeometry.to_scene(t1, CampusGeometry.tile_center(t1, 14, 13))
	_look(app, Vector3(wn.x, 0.05, wn.y), Vector3(wn.x, 1.18, wn.y - 6.0), 0.0)
	await _shot(app, "window-figure")
	quit()
