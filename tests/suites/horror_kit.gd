extends "res://tests/support/test_suite.gd"
## HorrorKit (procedural hands, heads, skin) and the stage lights of DeathStage.


func _rotations(node: Node) -> Array:
	var result := []
	for n: Node in node.find_children("*", "Node3D", true, false): result.append((n as Node3D).transform)
	return result


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if not (a[i] as Transform3D).is_equal_approx(b[i]): return false
	return true


func _vertices(node: Node) -> int:
	var count := 0
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		count += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return count


func test_hand() -> void:
	var hand := HorrorKit.hand({"quality": 2})
	var chains: Array = HorrorKit.hand_joints(hand)
	check(chains.size() == 5 and chains.all(func(c: Array) -> bool: return c.size() == 3), "a hand has a thumb and four fingers of three jointed phalanges")
	var nails := hand.find_children("Nail", "MeshInstance3D", true, false)
	check(nails.size() == 5 and hand.find_child("Forearm", true, false) != null and hand.find_child("Palm", true, false) != null, "forearm, palm and a nail on every finger")
	var extra := HorrorKit.hand({"quality": 2, "extra": true, "long": 1.4, "thin": 1.0})
	var extra_chains: Array = HorrorKit.hand_joints(extra)
	check(extra_chains[0].size() == 3 and extra_chains.slice(1).all(func(c: Array) -> bool: return c.size() == 4), "the extra-joint variant adds a phalanx to each finger, not the thumb")
	check((extra_chains[2][1] as Node3D).position.length() > (chains[2][1] as Node3D).position.length() * 1.15, "the long variant has longer phalanges")
	# Cached meshes and materials: a second hand shares them.
	var again := HorrorKit.hand({"quality": 2})
	check((again.find_child("Palm", true, false) as MeshInstance3D).mesh == (hand.find_child("Palm", true, false) as MeshInstance3D).mesh, "meshes are cached and shared")
	check((again.find_child("Palm", true, false) as MeshInstance3D).material_override == HorrorKit.skin("wax"), "skin materials are cached and shared")
	var low := HorrorKit.hand({"quality": 0})
	var high := HorrorKit.hand({"quality": 4})
	check(_vertices(low) * 2 < _vertices(high), "the low graphics tier builds a much lighter hand")
	# Posing is a pure function of its arguments.
	HorrorKit.pose_hand(hand, .6, .3, [null, [.1, .9, 1.2]], Vector2(.2, .1))
	var posed := _rotations(hand)
	HorrorKit.pose_hand(hand, -.2, 1.0)
	HorrorKit.pose_hand(hand, .6, .3, [null, [.1, .9, 1.2]], Vector2(.2, .1))
	check(_same(posed, _rotations(hand)), "the same pose arguments give the same joints, whatever came before")
	HorrorKit.pose_hand(again, .6, .3, [null, [.1, .9, 1.2]], Vector2(.2, .1))
	check(_same(posed, _rotations(again)), "two hands posed alike match exactly")
	check(is_equal_approx((chains[1][1] as Node3D).rotation.x, -.9), "per-finger joint angles are applied as given")
	HorrorKit.pose_hand(hand, 1.0, 0.0)
	check((chains[2][1] as Node3D).rotation.x < -1.0 and (chains[2][0] as Node3D).rotation.x < -1.0, "a full curl bends the finger towards the palm")
	var shadow := HorrorKit.hand({"tone": "shadow", "quality": 1})
	var shadow_mat := (shadow.find_child("Palm", true, false) as MeshInstance3D).material_override as ShaderMaterial
	check(shadow_mat != null and (shadow_mat.get_shader_parameter("base_color") as Color).get_luminance() < .05 and float(shadow_mat.get_shader_parameter("rim_emit")) > 0, "the shadow preset is near black with an edge light")
	for n: Node in [hand, extra, again, low, high, shadow]: n.free()


func test_head() -> void:
	var head := HorrorKit.head({"quality": 2})
	var skel := head.find_child("Skull", true, false) as Skeleton3D
	var face := head.find_child("Face", true, false) as MeshInstance3D
	check(skel != null and skel.get_bone_count() == 2 and face.skin != null and face.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES, "a head is a skinned face with a jaw bone")
	check(head.find_child("Mouth", true, false) != null and head.find_child("EyeL", true, false) != null and head.find_child("EyeR", true, false) != null, "a mouth cavity and two eyes deep in the sockets")
	HorrorKit.pose_head(head, .8)
	var open := skel.get_bone_pose_rotation(1)
	HorrorKit.pose_head(head, 0)
	check(skel.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY) and not open.is_equal_approx(Quaternion.IDENTITY), "the jaw opens and closes")
	HorrorKit.pose_head(head, .8)
	check(skel.get_bone_pose_rotation(1).is_equal_approx(open), "the jaw pose is a pure function of open")
	var blank := HorrorKit.head({"mouth": "none", "eyes": "hollow", "quality": 2})
	HorrorKit.pose_head(blank, 1)
	check(blank.find_child("Mouth", true, false) == null and blank.find_child("EyeL", true, false) == null and (blank.find_child("Skull", true, false) as Skeleton3D).get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY), "the no-mouth variant has no opening and empty sockets")
	var wide := HorrorKit.head({"mouth": "wide", "skew": 1, "neck": .4, "quality": 2})
	check(wide.find_child("Neck", true, false) != null and (wide.find_child("Face", true, false) as MeshInstance3D).mesh != face.mesh, "wide, skewed and long-necked variants are their own meshes")
	var eye_l := (wide.find_child("EyeL", true, false) as Node3D).position
	var eye_r := (wide.find_child("EyeR", true, false) as Node3D).position
	check(eye_l.y > eye_r.y + .005, "the skewed variant sets one eye higher")
	var second := HorrorKit.head({"quality": 2})
	check(second.find_child("Face", true, false).mesh == face.mesh, "head meshes are cached")
	for n: Node in [head, blank, wide, second]: n.free()


func test_stage_lights() -> void:
	var app: GameApp = APP.instantiate()
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/horror-kit/slot.json")
	app.settings = GameSettings.new(app.saves.side_path("settings.json"))
	root.add_child(app)
	await _frames(2)
	app.wuda_roll = func() -> float: return 1
	app.start_new_game("hard", "none")
	if app._opening_cut != null and app._opening_cut.on: app._opening_cut.end(true)
	else: app.ui._end_opening(true)
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	await _frames(2)
	var view := app.player.camera
	var env_before := view.environment
	var cg := DeathCG.new()
	app.add_child(cg)
	cg.begin("hand", app.player, app._campus_world(), app.ui, DeathCG.duration("hand", 0))
	var lights: Array = cg.stage_lights.duplicate()
	check(lights.size() >= 2 and view.environment != env_before and view.environment.fog_enabled, "a death shot builds its key light, motivated light and stage darkness")
	check(lights.all(func(l: Variant) -> bool: return not (l as Light3D).shadow_enabled), "stage lights cast no shadows")
	cg.update(cg.dur * .7)
	var hand: Node3D = cg.shots.p["hand"]
	check(hand.visible and hand.has_meta("horror_hand"), "the back-seat shot has a HorrorKit hand on the shoulder")
	var pose := _rotations(hand)
	cg.update(cg.dur * .2)
	cg.update(cg.dur * .7)
	check(_same(pose, _rotations(hand)), "the shoulder hand's pose follows the timeline without accumulating")
	# Restart: the second stage restores the first one's environment before taking its own.
	cg.begin("patrol", app.player, app._campus_world(), app.ui, DeathCG.duration("patrol", 0))
	check(lights.all(func(l: Variant) -> bool: return not is_instance_valid(l) or (l as Light3D).is_queued_for_deletion()), "restarting releases the previous stage lights")
	check(cg._env_previous == env_before, "restarting keeps the player's own environment to restore")
	cg.update(cg.dur * .5)
	var second: Array = cg.stage_lights.duplicate()
	cg.finish()
	check(cg.stage_lights.is_empty() and second.all(func(l: Variant) -> bool: return not is_instance_valid(l) or (l as Light3D).is_queued_for_deletion()), "finishing releases every stage light")
	check(view.environment == env_before, "finishing restores the camera's environment")
	# Cancelling by freeing the stage also cleans up.
	var cancelled := DeathCG.new()
	app.add_child(cancelled)
	cancelled.begin("garage", app.player, app._campus_world(), app.ui, DeathCG.duration("garage", 0))
	cancelled.update(1.0)
	var owned: Array = cancelled.stage_lights.duplicate()
	cancelled.queue_free()
	await _frames(2)
	check(view.environment == env_before and owned.all(func(l: Variant) -> bool: return not is_instance_valid(l)), "a freed stage leaves no lights or environment behind")
	# The crowd's lift is lit by one strip light of its own (the stage's dark environment and one motive light), and
	# frees both with the stage.
	var crowd := DeathCG.new()
	app.add_child(crowd)
	crowd.begin("crowd", app.player, app._campus_world(), app.ui, 4.2)
	var crowd_lights: Array = crowd.stage_lights.duplicate()
	check(view.environment != env_before and crowd_lights.size() == 1, "the crowd stage lights its lift with one strip light of its own")
	crowd.finish()
	crowd.queue_free()
	await _frames(2)
	check(view.environment == env_before and crowd_lights.all(func(l: Variant) -> bool: return not is_instance_valid(l)), "the crowd stage leaves no light or environment behind")
	cg.queue_free()
	app.return_to_menu()
	app.queue_free()
	await _frames(3)
	CampusData.clear_caches()
