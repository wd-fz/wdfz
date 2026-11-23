extends SceneTree
## A real client holds the normal movement action while the other process owns
## campus collision. Deliberate host frame stalls complement the UDP fault proxy.
var app: GameApp
var network: LanSession
var hosting := false
var port := 0
var starting := false
var reserved := false
var checks := 0
var failures := 0
var last_authority := Vector3.ZERO


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--role=host": hosting = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)


func room_changed(_data: Dictionary) -> void:
	if network.room.phase != "lobby" or not network.room.members.has(network.local_id): return
	var member: Dictionary = network.room.members[network.local_id]
	if not hosting and member.character != "xu":
		if not reserved:
			reserved = true
			network.select_character("xu")
		return
	if not member.ready: network.ready(true, "none")
	if hosting and not starting and network.room.can_start():
		starting = true
		check(network.start().is_empty(), "authority starts the confirmed squad")


func motion(data: Dictionary) -> void:
	var local: Dictionary = data.players.get(network.local_id, {})
	if local.get("world") != "out": return
	var p: Array = local.pose.position
	last_authority = Vector3(p[0],p[1],p[2])


func run() -> void:
	app = preload("res://game/app/app.tscn").instantiate()
	app.saves = SaveStore.new("user://walking/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	app.settings.set_value("quality",0)
	app.settings.set_value("fps_limit",60)
	root.add_child(app)
	await process_frame
	network = app.lan.network
	network.room_changed.connect(room_changed)
	network.motion_received.connect(motion)
	var reason := network.host("walking","host",port) if hosting else network.join("127.0.0.1:%d" % port,"guest-1")
	check(reason.is_empty(),"real ENet connection starts")
	var deadline := Time.get_ticks_msec()+120000
	var checked_barrier := false
	while Time.get_ticks_msec()<deadline and (not app.lan.playing() or network.room.phase!="playing"):
		if not checked_barrier and network.room != null and network.room.phase == "loading":
			checked_barrier = true
			check(app.ui.loading() and not app.player.enabled, "the full application keeps a loading cover and no control during the shared barrier")
		await process_frame
	print("PLAY: ", "host" if hosting else "guest", " ", Time.get_ticks_msec())
	if not app.lan.playing() or network.room.phase!="playing":
		check(false,"both full applications enter the campus")
	else:
		check(checked_barrier and network.is_ready() and not app.ui.loading(), "the group enters only after local readiness and the room's playing phase")
		var notice := app.ui.get_node("%Toast") as Label
		check(notice.text == OpeningStory.handover(app.session.character_id), "each new co-op player sees their own character and the first lead")
		if hosting:
			for actor: CooperativeActor in network.simulation.actors.values():
				network.simulation.travel(actor,"out",{"position":[76.,.05,74.],"yaw":0.,"pitch":0.})
		while app.session.world_id != "out" and Time.get_ticks_msec()<deadline: await physics_frame
		print("FIELD: ", "host" if hosting else "guest", " ",app.session.world_id, " ",Time.get_ticks_msec())
		check(app.session.world_id=="out","the campus applies the outdoor authority frame")
		await create_timer(.8).timeout
		if hosting: await observe_student()
		else: await walk()
	print("LAN RESULT: ",JSON.stringify({"role":"host" if hosting else "guest-1","checks":checks,"failures":failures}))
	app.return_to_menu()
	app.queue_free()
	await process_frame
	quit(1 if failures else 0)


func observe_student() -> void:
	var saw_walking := false
	var saw_stop := false
	var at_door := false
	var deadline := Time.get_ticks_msec()+120000
	var frame := 0
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		frame += 1
		if saw_walking and frame % 93 == 0: OS.delay_msec(270)
		var connected := false
		for id: String in network.room.members:
			if id == network.local_id: continue
			connected = network.room.members[id].connected
			var remote := network.simulation.actor(id)
			if not at_door and remote.pose.pitch > .65:
				print("Guest requested school doorway")
				at_door = true
				var layout := CampusData.layout("teach1")
				var entry := CampusGeometry.door_port(layout,CampusData.campus().campus_doors.doors[0])
				var normal: Vector2 = entry.n
				var start := CampusGeometry.to_scene(layout,entry.p)-normal*1.25
				network.simulation.travel(remote,"teach1",{"position":[start.x,.05,start.y],"yaw":atan2(-normal.x,-normal.y),"pitch":0.})
			var figure: Node3D = app.lan.avatars.peers.get(id)
			if figure != null:
				var avatar: StudentAvatar = figure.get_child(0)
				if avatar.character=="xu" and avatar.clip=="walk": saw_walking=true
				if saw_walking and avatar.clip=="idle": saw_stop=true
		if not connected: break
	check(saw_walking,"the host sees the selected guest animate while travelling")
	check(saw_stop,"the remote feet return to idle when the guest releases the movement action")


func walk() -> void:
	var start := app.player.global_position
	var previous := start
	var reverse_ticks := 0
	var worst := 0.0
	Input.action_press("move_forward")
	for i in 240:
		await physics_frame
		var at := app.player.global_position
		var backward := at.z-previous.z
		if backward>.002:
			reverse_ticks += 1
			worst = maxf(worst,backward)
		previous=at
	Input.action_release("move_forward")
	check(start.z-previous.z>5.0,"holding forward moves the guest through the field")
	check(reverse_ticks==0,"late input and host frame stalls never reverse a forward stride")
	for i in 120: await physics_frame
	var error := last_authority.distance_to(app.player.position)
	check(error<.08,"after stopping the guest and the authority converge within eight centimetres")
	print("WALK: distance_m=",start.z-previous.z," reverse_ticks=",reverse_ticks," max_reverse_m=",worst," stopped_error_m=",error)

	# Looking up signals the host to place this guest just inside the real school door.
	app.player.set_pitch(.72)
	var deadline := Time.get_ticks_msec()+20000
	while app.session.world_id!="teach1" and Time.get_ticks_msec()<deadline: await physics_frame
	check(app.session.world_id=="teach1","the host places the client inside the building")
	if app.session.world_id!="teach1": return
	for i in 20: await physics_frame
	# Let movement packets through while deliberately withholding reliable baselines.
	# A delayed pre-crossing snapshot must not send us back through the door.
	var old_snapshot := app.lan.current.duplicate(true)
	network.snapshot_received.disconnect(app.lan._snapshot)
	var ahead := -app.player.global_basis.z
	start = app.player.global_position
	previous = start
	reverse_ticks = 0
	var worst_forward := 0.
	Input.action_press("move_forward")
	for i in 105:
		await physics_frame
		var at := app.player.global_position
		var step := (at-previous).dot(ahead)
		if step < -.002: reverse_ticks += 1
		worst_forward = maxf(worst_forward,step)
		previous=at
	Input.action_release("move_forward")
	check(app.session.world_id=="out" and (previous-start).dot(ahead)>2.0,"holding one direction crosses the ordinary teaching-building threshold")
	check(reverse_ticks==0 and worst_forward<.13,"crossing spaces preserves motion and camera position without a backwards or double stride")
	var current_region := app.lan._view_scene
	network.snapshot_received.connect(app.lan._snapshot)
	app.lan._snapshot(old_snapshot)
	check(app.session.world_id=="out" and app.lan._view_scene==current_region,"an older reliable snapshot cannot undo an already presented crossing")
	print("DOOR: distance_m=",(previous-start).dot(ahead)," reverse_ticks=",reverse_ticks," max_forward_m=",worst_forward)
