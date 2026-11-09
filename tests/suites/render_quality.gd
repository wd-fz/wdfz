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
