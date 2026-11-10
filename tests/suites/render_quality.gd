extends "res://tests/support/test_suite.gd"
## Lighting and renderer budget per picture quality (CampusLighting.apply_quality, RenderQuality).


func test_lighting_tiers() -> void:
	var light := CampusLighting.new()
	root.add_child(light)
	light.setup("teach1", CampusData.layout("teach1"), null, 0)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	var keep_q := CampusLighting.quality
	var keep_m := CampusLighting.mobile_renderer
	var sums := []
	var terms := []
	for q in 5:
		CampusLighting.quality = q
		CampusLighting.mobile_renderer = false
		light.apply_quality()
		check(light.env.ssao_enabled == bool(CampusLighting.Q_SSAO[q]) and light.env.glow_enabled == bool(CampusLighting.Q_GLOW[q]) and light.env.volumetric_fog_enabled == bool(CampusLighting.Q_VOLUMETRIC[q]),
			"quality %d: SSAO %s, glow %s, volumetric fog %s" % [q, CampusLighting.Q_SSAO[q], CampusLighting.Q_GLOW[q], CampusLighting.Q_VOLUMETRIC[q]])
		light.update(0.0, 700.0, cam)
		light._pick_shadow_lamps(cam)
		var lit := 0
		var sum := 0.0
		for l: OmniLight3D in light.room_lights:
			lit += 1 if l.light_energy > 0.0 else 0
			sum += l.light_energy
		check(light.shadow_lamps() == mini(int(CampusLighting.Q_LAMP_SHADOWS[q]), lit), "quality %d: the %d nearest lamps cast shadows" % [q, light.shadow_lamps()])
		sums.append(sum)
		terms.append(light.terms.duplicate())
	check(same_json(terms[0], terms[4]), "the original lightState terms do not depend on quality")
	check(is_equal_approx(float(sums[4]) / float(sums[0]), float(CampusLighting.Q_LAMP_GAIN[4])) and float(CampusLighting.Q_INDOOR_AMB[4]) < 1.0,
		"from 精细 up the lamps carry more of the light and the flat ambient less")
	CampusLighting.mobile_renderer = true
	CampusLighting.quality = 4
	light.apply_quality()
	check(not light.env.ssao_enabled and not light.env.volumetric_fog_enabled and not light.env.glow_enabled, "Mobile disables unsupported effects and the glow replay deadlock trigger")
	CampusLighting.quality = keep_q
	CampusLighting.mobile_renderer = keep_m
	cam.queue_free()
	light.queue_free()
	await _frames(1)
	var vp := SubViewport.new()
	root.add_child(vp)
	var r0 := RenderQuality.apply(vp, 0, false)
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and vp.positional_shadow_atlas_size == 0 and bool(r0["fsr"]), "流畅 upscales with FSR and has no lamp shadow atlas")
	var mobile_low := RenderQuality.apply(vp, 0, true)
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and not bool(mobile_low["fsr"]), "Mobile resets unsupported FSR to its supported bilinear scaler")
	RenderQuality.apply(vp, 4, false)
	check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and vp.positional_shadow_atlas_size == 4096 and vp.mesh_lod_threshold < 1.0, "真实 renders at full size with a large shadow atlas and fine LODs")
	vp.msaa_3d = Viewport.MSAA_DISABLED
	RenderQuality.apply(vp, 2, false)
	check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "精细 smooths edges with FXAA where MSAA is off")
	RenderQuality.apply(vp, 2, true)
	check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Mobile clears FXAA so archive replay can render without stalling")
	vp.msaa_3d = Viewport.MSAA_4X
	RenderQuality.apply(vp, 3, true)
	check(vp.msaa_3d == Viewport.MSAA_4X and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "Mobile keeps the higher tier's MSAA without enabling FXAA")
	vp.queue_free()
	CampusData.clear_caches()


func test_torch() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/render-quality-save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/render-quality.json")
	root.add_child(app)
	await _frames(2)
	app._setting_changed("quality", 2)
	var expected_aa := Viewport.SCREEN_SPACE_AA_DISABLED if RenderingServer.get_current_rendering_method() == "mobile" else Viewport.SCREEN_SPACE_AA_FXAA
	check(root.screen_space_aa == expected_aa, "app settings apply the antialiasing policy for the active renderer")
	var torch := app.player.camera.get_node("Torch") as SpotLight3D
	check(torch.shadow_enabled and torch.light_cull_mask == CampusLighting.WORLD_LIGHT_MASK and torch.position.x > 0.05, "the torch is held in the hand, casts shadows and leaves the hands to their own light")
	app._setting_changed("quality", 0)
	check(not torch.shadow_enabled and CampusLighting.quality == 0, "流畅 turns the torch shadow off")
	app.queue_free()
	await _frames(2)


func test_daylight_and_glow() -> void:
	# Windows found from the room model, daylight through them by day, the lamp gain capped in the normal-coloured world.
	var keep_q := CampusLighting.quality
	var keep_m := CampusLighting.mobile_renderer
	CampusLighting.mobile_renderer = false
	CampusLighting.quality = 2
	var model := (load(CampusData.scene_path("teach1")) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	# As CampusWorld does: instanced pieces (the panes among them) become MultiMeshes.
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("extras") and (mesh.get_meta("extras") as Dictionary).has("wdfz_instances"):
			CampusWorld._to_multimesh(mesh)
	var light := CampusLighting.new()
	root.add_child(light)
	light.setup("teach1", CampusData.layout("teach1"), model, 0)
	if DisplayServer.get_name() == "headless":
		# The dummy renderer keeps no mesh data, so the panes cannot be read: there are simply no window lights.
		check(light.windows.is_empty() and light.window_lights.is_empty(), "without mesh data (headless) no window lights are made")
		light.update(0.0, 700.0, null)
		CampusLighting.quality = keep_q
		CampusLighting.mobile_renderer = keep_m
		light.queue_free()
		model.queue_free()
		await _frames(1)
		CampusData.clear_caches()
		return
	var north := 0
	for w: Dictionary in light.windows:
		north += 1 if (w["out"] as Vector3).is_equal_approx(Vector3(0, 0, -1)) else 0
	check(light.windows.size() == 12 and north == 12 and light.window_lights.size() == 12, "teach1 has twelve outer windows, all on the north wall (found %d)" % light.windows.size())
	var w0: Dictionary = light.windows[0]
	var spot0 := light.window_lights[0]
	check(absf(float(w0["h"]) - 1.45) < 0.05 and spot0.position.z > (w0["at"] as Vector3).z and (-spot0.global_basis.z).z > 0.5 and (-spot0.global_basis.z).y < -0.3 and spot0.light_projector != null,
		"a window light sits just inside its pane, points into the room and down, and carries the window shape")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = (w0["at"] as Vector3) + Vector3(0, 0, 2)
	light.update(0.0, 700.0, cam)
	light._pick_shadow_windows(cam)
	var lit := 0
	var shadowed := 0
	for spot: SpotLight3D in light.window_lights:
		lit += 1 if spot.visible and spot.light_energy > 1.0 else 0
		shadowed += 1 if spot.shadow_enabled else 0
	check(lit == 12 and shadowed == int(CampusLighting.Q_LAMP_SHADOWS[2]), "by day every window gives light and the nearest one casts shadows")
	var day_amb := light.env.ambient_light_energy
	light.update(0.0, 1380.0, cam)
	check(not light.window_lights[0].visible, "no daylight at night")
	light.update(0.0, 700.0, cam)
	light.blackout = true
	light.update(0.0, 700.0, cam)
	check(not light.window_lights[0].visible, "nor in a blackout")
	light.blackout = false
	CampusLighting.quality = 0
	light.apply_quality()
	light.update(0.0, 700.0, cam)
	check(not light.window_lights[0].visible and light.env.ambient_light_energy > day_amb and is_equal_approx(light.room_lights[0].position.y, float(light.room_lights[0].get_meta("rest_y"))),
		"流畅 keeps the old flat light: no window light, full ambient, lamps where the old build put them")
	CampusLighting.quality = 3
	light.apply_quality()
	light.world_normal = 0.0
	light.update(0.0, 700.0, cam)
	var dark_world := light.room_lights[0].light_energy
	var terms_pt := float(light.terms["pt"])
	light.world_normal = 1.0
	light.update(0.0, 700.0, cam)
	var gain_normal := light.room_lights[0].light_energy / (float(light.terms["pt"]) / terms_pt) / dark_world * float(CampusLighting.Q_LAMP_GAIN[3])
	check(absf(gain_normal - CampusLighting.NORMAL_LAMP_GAIN) < 0.05 and is_equal_approx(light.room_lights[0].position.y, float(light.room_lights[0].get_meta("rest_y")) - CampusLighting.LAMP_DROP) and light.env.glow_hdr_threshold >= 1.0,
		"in the normal-coloured world the lamp gain is capped (%.2f) and the light hangs clear of the ceiling" % gain_normal)
	light.world_normal = 0.0
	CampusLighting.quality = keep_q
	CampusLighting.mobile_renderer = keep_m
	cam.queue_free()
	light.queue_free()
	model.queue_free()
	await _frames(1)
	CampusData.clear_caches()


func test_scene_materials() -> void:
	var wall := StandardMaterial3D.new()
	wall.resource_name = "MeshPhongMaterial"
	var metal := StandardMaterial3D.new()
	metal.resource_name = "MeshPhongMaterial"
	var glass := StandardMaterial3D.new()
	glass.resource_name = "MeshPhongMaterial"
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pbr := StandardMaterial3D.new()
	pbr.resource_name = "MeshStandardMaterial"
	pbr.metallic = 0.7
	check(SceneMaterials.shininess_of(wall, 0.7) == 0 and SceneMaterials.shininess_of(metal, 0.6) == 40 and SceneMaterials.shininess_of(wall, 0.96) == 4 and SceneMaterials.shininess_of(pbr, 0.33) == -1,
		"the old shininess is read back from the exported roughness (0.70 was shininess 0)")
	check(is_equal_approx(SceneMaterials.physical_roughness(40), 1.0 - sqrt(40.0 / 90.0)) and SceneMaterials.physical_roughness(0) == 0.96 and SceneMaterials.physical_roughness(90) == 0.22, "the old build's physical roughness formula, clamped")
	for q in 5:
		check(is_equal_approx(float(SceneMaterials.response(wall, 0.7, q)["roughness"]), 0.96), "walls and ceilings are matte at quality %d" % q)
	check(is_equal_approx(float(SceneMaterials.response(metal, 0.6, 0)["roughness"]), 0.6) and float(SceneMaterials.response(metal, 0.6, 1)["metallic"]) == 0.0, "流畅 and 均衡 keep the exported response of everything else")
	var mr := SceneMaterials.response(metal, 0.6, 2)
	check(absf(float(mr["roughness"]) - 0.333) < 0.01 and is_equal_approx(float(mr["metallic"]), SceneMaterials.MID_TIER_METALLIC), "from 精细 metal is smoother and slightly metallic")
	check(is_equal_approx(float(SceneMaterials.response(glass, 0.4, 3)["roughness"]), 0.05) and absf(float(SceneMaterials.response(wall, 0.94, 2)["roughness"]) - 0.742) < 0.01, "glass is polished, floor tiles get their sheen")
	var pr := SceneMaterials.response(pbr, 0.33, 4)
	check(is_equal_approx(float(pr["roughness"]), 0.33) and is_equal_approx(float(pr["metallic"]), 0.7), "真实's own physical materials are left alone")
	# On a real model: idempotent, and a later quality starts again from the file's values.
	var model := (load("res://assets/campus/scenes/teach1.glb") as PackedScene).instantiate() as Node3D
	var first := SceneMaterials.apply(model, 2)
	var again := SceneMaterials.apply(model, 2)
	var back := SceneMaterials.apply(model, 0)
	var glossy_walls := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null and String(m.resource_name).begins_with("MeshPhongMaterial") and is_equal_approx(m.roughness, 0.7):
				glossy_walls += 1
	check(first > 0 and again == 0 and back > 0 and glossy_walls == 0, "applying is idempotent, reversible by quality, and leaves no half-glossy wall (%d changed)" % first)
	SceneMaterials.apply(model, CampusLighting.quality)
	model.free()
