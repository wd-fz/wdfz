extends SceneTree
## Prediction and authority see identical floor/wall collision in a rotated region.
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)


func solid(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.position = at


func student(parent: Node3D) -> PlayerController:
	var body := preload("res://game/presentation/actors/player.tscn").instantiate() as PlayerController
	parent.add_child(body)
	body.enabled = true
	body.network_driven = true
	return body


func walk_trace() -> void:
	var frame := Node3D.new()
	frame.rotation.y = 1.14
	root.add_child(frame)
	solid(frame, Vector3(0,-.25,0), Vector3(32,.5,32))
	solid(frame, Vector3(0,1,-2.8), Vector3(16,2,.25))
	var local := student(frame)
	var host := student(frame)
	var actor := CooperativeActor.new()
	var prediction := LanPrediction.new()
	var window: Array = []
	var deliveries: Array = []
	var reported: Array = []
	var max_back := 0.0
	var worst := 0.0
	var postures := {}
	var max_wall := 0.0
	const DT := 1.0/60
	for i in range(1,285):
		await physics_frame
		var axis := Vector2.ZERO
		if i <= 100: axis = Vector2.UP
		elif i <= 145: axis = Vector2.RIGHT
		elif i <= 184: axis = Vector2(.33,.60)
		var run_key := i > 66 and i <= 145
		var before := local.position
		local.step_movement(axis,run_key,DT)
		prediction.advance(local,DT,local.position-before)
		prediction.record(i,local.position)
		postures[i] = local.position
		if i <= 100: max_back = maxf(max_back,local.position.z-before.z)
		window.append([axis.x,axis.y,0.,0.,run_key,false,{}])
		if window.size()>LanProtocol.INPUT_WINDOW: window.pop_front()
		if i%2 == 0 and i%18 != 0:
			var packet := {"scene":1,"seq":i,"frames":window.duplicate(true)}
			deliveries.append([i+(7 if i%12==0 else 3),packet])
			if i%10==0: deliveries.append([i+9,packet])
		for due: Array in deliveries.duplicate():
			if int(due[0]) > i: continue
			actor.queue_inputs(LanProtocol.inputs(due[1]))
			deliveries.erase(due)
		actor.consume_input()
		var input := actor.input
		host.step_movement(Vector2(input.x,input.y),input.run,DT)
		if actor.processed_sequence > 0:
			worst = maxf(worst,host.position.distance_to(postures[actor.processed_sequence]))
		if i%3 == 0:
			reported.append([i+5,host.position,actor.processed_sequence])
		if not reported.is_empty() and reported.front()[0] <= i:
			var report: Array = reported.pop_front()
			prediction.reconcile(local,report[1],report[2],true)
		max_wall = minf(max_wall,host.position.z)
	check(max_back<.002, "walking into a wall never takes a backwards step under latency, jitter, duplicate and lost inputs")
	check(worst<.012, "host acknowledges the exact colliding walk, sprint, analog strafe and stop samples (%.4f m)" % worst)
	check(max_wall > -2.40 and max_wall < -2.30, "the shared motor stops at the wall without penetrating it")
	check(local.position.x > 3.0 and local.position.distance_to(host.position)<.012, "stopping converges with no drift after reversing")
	var packed := {"scene":1,"seq":285,"frames":window.duplicate(true)}
	packed.frames[1][0] = 12
	check(LanProtocol.inputs(packed).is_empty(), "one malformed input rejects the whole packet")
	var original := local.position
	prediction.clear()
	prediction.record(1,original)
	prediction.reconcile(local,original+Vector3(.15,0,0),1,true)
	check(local.position == original, "ordinary corrections do not teleport the camera on packet arrival")
	for i in 32:
		prediction.advance(local,DT)
		await physics_frame
	check(local.position.distance_to(original+Vector3(.15,0,0))<.006, "a genuine small error converges in the rotated collision frame")
	prediction.record(2,local.position)
	var rotated := Transform3D(Basis(Vector3.UP,PI/2),Vector3(3,0,5))
	prediction.rebase(rotated)
	prediction.reconcile(local,rotated*local.position,2,true)
	check(prediction.error_metres<.002, "unacknowledged history follows seamless region rebasing")
	prediction.record(3,local.position)
	var forced := Vector3(3,0,1)
	prediction.reconcile(local,forced,3,true)
	check(local.position==forced and local.velocity==Vector3.ZERO, "a real authoritative displacement snaps and clears momentum")
	check(prediction.history.is_empty(), "an authoritative teleport discards old prediction history")
	for seq in range(4, 4 + LanPrediction.HISTORY_LIMIT + 2): prediction.record(seq, local.position)
	prediction.reconcile(local, forced + Vector3.RIGHT, 4, true)
	check(local.position == forced + Vector3.RIGHT and prediction.history.is_empty(), "confirmations older than the bounded history recover once at the host pose")
	prediction.reconcile(local, forced, 5, true)
	check(local.position == forced + Vector3.RIGHT, "other outdated acknowledgments cannot drag the recovered player back")
	prediction.clear()
	var delayed_start := local.position
	prediction.record(1,local.position)
	prediction.reconcile(local,local.position+Vector3.LEFT*.70,1,true)
	var backwards := 0.0
	for i in 50:
		var before := local.position
		local.move_and_collide(frame.global_basis * Vector3.RIGHT * .025)
		prediction.advance(local,DT,local.position-before)
		backwards = maxf(backwards, before.x-local.position.x)
		await physics_frame
	check(backwards<.0001 and local.position.x-delayed_start.x<.60, "a late partial correction converges without a backwards step even while the host is CPU-stalled")
	frame.queue_free()
	await process_frame


func cast_checks() -> void:
	var room := CooperativeRoom.new()
	for id: String in ["a","b","c","d"]:
		room.add_member(id,id,id=="a")
		room.ready(id,true,"tech")
	check(room.select_character("a","xu").is_empty() and not room.members.a.ready, "confirming a role releases readiness")
	check(not room.select_character("b","xu").is_empty() and room.members.b.ready, "simultaneous overlapping choices preserve the first owner")
	check(not room.select_character("a","invalid").is_empty(), "unknown character is rejected")
	room.ready("a",true,"tech")
	room.begin("characters")
	var used := {}
	for m: Dictionary in room.members.values(): used[m.character] = true
	check(used.size()==4 and room.members.a.character=="xu", "four automatic and explicit picks always resolve uniquely")
	check(not room.select_character("b","xu").is_empty(), "active roster is immutable")
	for id: String in room.members: room.loaded(id)
	var sim := CooperativeSimulation.new()
	root.add_child(sim)
	sim.setup(room,777)
	var a := sim.actor("a")
	room.disconnect_member("a")
	room.reconnect("a")
	check(a.session.character_id=="xu" and room.members.a.character=="xu", "reconnection keeps the chosen avatar and talent")
	var save := sim.capture()
	check(CooperativeValidation.validate(save).is_empty(), "character roster and personal save validate")
	var mismatched := save.duplicate(true)
	mismatched.actors.a.session.character = "lin"
	check(not CooperativeValidation.validate(mismatched).is_empty(), "a mismatched member and session role is rejected before restoring any actor")
	var old := save.duplicate(true)
	for id: String in old.room.members:
		old.room.members[id].erase("character")
		old.actors[id].session.erase("character")
	check(CooperativeValidation.validate(old).is_empty(), "pre-cast saves still validate")
	var restored_room := CooperativeRoom.new()
	restored_room.members = old.room.members.duplicate(true)
	restored_room.assign_characters()
	var old_ids := []
	for m: Dictionary in restored_room.members.values(): old_ids.append(m.character)
	check(old_ids == StudentCast.IDS, "a legacy squad gets four stable distinct characters")
	a.school().seated = false
	a.bag().torch_on = true
	(a.feature(&"body.injury") as BodyModule).treat = {"t":0.0}
	var motion := sim.motion("b")
	check(motion.players.a.act=="bandage" and int(motion.players.a.gear)==1, "remote animation and hand props follow authoritative state")
	check(LanProtocol.encode(motion).size()<1200, "four full-size characters and actions still fit a motion datagram")
	sim.travel(a,"out",sim.spawn("out"))
	var version := a.scene_version
	var prior_pose := a.pose.duplicate(true)
	sim.input(a.id,{"epoch":room.epoch,"scene":version,"seq":5,"frames":[[0,-1,0,0,false,false,{}]]})
	sim.travel(a,"teach1",prior_pose,true)
	sim.input(a.id,{"epoch":room.epoch,"scene":version,"seq":6,"frames":[[0,-1,0,0,false,false,{}]]})
	a.consume_input()
	check(a.processed_sequence==5 and a.input.y==-1 and is_equal_approx(a.input.yaw,a.frame_yaw), "a rotated doorway preserves queued heading")
	a.consume_input()
	check(a.processed_sequence==6 and is_equal_approx(a.input.yaw,a.frame_yaw), "late input from the adjacent frame crosses only a seamless doorway")
	sim.travel(a,"out",sim.spawn("out"))
	sim.input(a.id,{"epoch":room.epoch,"scene":version,"seq":9,"frames":[[1,0,0,0,true,false,{}]]})
	a.consume_input()
	check(a.processed_sequence==6 and a.input.x==0 and not a.input.run, "hard travel rejects input from the old scene")
	sim.queue_free()
	await process_frame
	var avatar := StudentAvatar.new()
	root.add_child(avatar)
	for id: String in StudentCast.IDS:
		avatar.dress(id)
		check(avatar.skeleton.get_bone_count()>=23 and avatar.animation.get_animation_list().size()>=26, id+" imports as a fully animated human rig")
		avatar.advance("walk",.14)
		var thigh: int = avatar.skeleton.find_bone("ThighR")
		var first := avatar.skeleton.get_bone_pose_rotation(thigh)
		avatar.advance("walk",.49)
		check(first.angle_to(avatar.skeleton.get_bone_pose_rotation(thigh))>.24, id+" strides articulate the actual leg bones")
		avatar.advance("walk",.11,1.0,0,0.0,"interact")
		check(avatar.clip=="walk" and avatar._upper_tracks.interact.size()>=6, "operating a door preserves the real stride underneath the upper-body reach")
		avatar.advance("sit",.01)
		check(avatar.clip=="sit_down", "standing player sits via a transition")
		avatar.advance("sit",.66)
		check(avatar.clip=="sit", "sit transition settles into the seated loop")
		avatar.advance("idle",.01)
		check(avatar.clip=="stand_up", "standing up has its own transition")
		avatar.advance("idle",.70)
		avatar.advance("down",.01)
		avatar.advance("down",1.0)
		check(avatar.clip=="down", "collapse settles without repeating the fall")
	avatar.dress("xu")
	var cloth:=avatar.skeleton
	var hem:=cloth.find_bone("Hem00")
	check(hem>=0 and cloth.get_bone_parent(hem)==cloth.find_bone("Hips"),"the skirt has an independent waist-mounted hem")
	if hem>=0:
		var intact:=true
		for action: String in ["idle","run","left","sit_down","sit","crouch"]:
			avatar.animation.play(action,0.0)
			for step in 9:
				avatar.animation.seek(avatar.animation.current_animation_length*step/9,true)
				for j in 12:
					var edge_start:=cloth.get_bone_global_pose(cloth.find_bone("Hem%02d"%j)).origin
					var edge_end:=cloth.get_bone_global_pose(cloth.find_bone("Hem%02d"%((j+1)%12))).origin
					intact = intact and edge_start.is_finite() and edge_start.distance_to(edge_end)<.38
		check(intact,"hem stays connected through full strides, strafing, crouching and sitting")
	avatar.queue_free()
	await process_frame


func run() -> void:
	await walk_trace()
	await cast_checks()
	print("LAN MOVEMENT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
