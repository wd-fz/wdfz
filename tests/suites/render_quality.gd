extends "res://tests/support/test_suite.gd"
## The new budget deliberately replaces old photorealistic preset assertions.

func test_lighting_tiers() -> void:
	var light := CampusLighting.new()
	root.add_child(light)
	light.setup("teach1", CampusData.layout("teach1"), null, 0)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = light.room_lights[0].global_position
	for q in 5:
		light.options = GraphicsProfile.preset(q)
		# Retired fields from an old/custom caller cannot bring expensive passes back.
		light.options.merge({"ssao":4,"glow":1,"volumetric_fog":1,"lamp_shadows":4,"window_shadows":4}, true)
		light.apply_quality(cam)
		light.update(0, 700, cam)
		light._select_local_lights(cam)
		check(not light.env.ssao_enabled and not light.env.glow_enabled and not light.env.volumetric_fog_enabled,
			"tier %d cannot enable retired multipass effects" % q)
		check(light.local_light_count() > 0 and light.local_light_count() <= int(CampusLighting.LOCAL_LIGHT_LIMIT[q]) and light.shadow_lamps() == 0,
			"tier %d has a bounded local fill pool without omni shadows" % q)
		check(light.sun_light.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and light.sun_light.directional_shadow_max_distance <= 32,
			"an indoor sun uses one bounded shadow map at tier %d" % q)
	cam.position = Vector3(1000, 1.6, 1000)
	light._select_local_lights(cam)
	check(light.local_light_count() == 0, "distant invisible lamps consume no local light budget")
	cam.queue_free()
	light.queue_free()
	var vp := SubViewport.new()
	vp.size = Vector2i(2560, 1440)
	root.add_child(vp)
	for q in 5:
		var options := GraphicsProfile.preset(q)
		for mobile in ([false, true] if DisplayServer.get_name() == "headless" else [RenderingServer.get_current_rendering_method() == "mobile"]):
			RenderQuality.apply(vp, q, mobile, options)
			check(vp.msaa_3d <= Viewport.MSAA_2X and vp.positional_shadow_atlas_size <= 2048 and vp.mesh_lod_threshold >= 1.0,
				"tier %d cannot grow MSAA, shadows or LOD past the work budget" % q)
			check(vp.scaling_3d_scale <= 0.75 and (vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR if mobile else vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR),
				"high resolution screens obey the pixel budget on both renderers")
	RenderQuality.apply(vp, 4, true, {"msaa":3,"shadow_resolution":3,"shadow_filter":5,"lod_detail":3})
	check(vp.msaa_3d == Viewport.MSAA_2X and vp.positional_shadow_atlas_size == 2048, "old direct rendering options are capped too")
	vp.queue_free()
	await _frames(1)


func test_pixel_budget() -> void:
	for size in [Vector2i(960,540), Vector2i(2340,1080), Vector2i(3200,1440), Vector2i(3840,2160), Vector2i(1080,2340)]:
		for q in 5:
			var result := RenderQuality.resolution(size, GraphicsProfile.preset(q))
			var drawn: Vector2i = result.size
			var edge := int(RenderQuality.HEIGHTS[q])
			check(drawn.x * drawn.y <= ceil(edge * edge * 16.0 / 9.0) and drawn.x <= size.x and drawn.y <= size.y,
				"%s tier %d stays inside its pixel budget and never supersamples" % [size,q])
			check(absf(float(drawn.x) / drawn.y - float(size.x) / size.y) < .01, "pixel budgeting preserves the display aspect ratio")
	var native := RenderQuality.resolution(Vector2i(2560,1440), {"render_budget":5,"render_scale":100})
	check(native.size == Vector2i(2560,1440), "an explicit native-resolution custom choice remains available")


func test_torch() -> void:
	var app := APP.instantiate() as GameApp
	app.saves = SaveStore.new(_test_path.get_base_dir() + "/render-quality-save.json")
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/render-quality.json")
	root.add_child(app)
	await _frames(2)
	app._setting_changed("quality", 2)
	var expected_aa := Viewport.SCREEN_SPACE_AA_DISABLED if RenderingServer.get_current_rendering_method() == "mobile" else Viewport.SCREEN_SPACE_AA_FXAA
	check(root.screen_space_aa == expected_aa, "the renderer's antialiasing workaround is retained")
	var torch := app.player.camera.get_node("Torch") as SpotLight3D
	check(torch.shadow_enabled and torch.light_cull_mask == CampusLighting.WORLD_LIGHT_MASK and torch.position.x > 0.05, "the held torch retains useful directional shadows without lighting the hands")
	app._setting_changed("quality", 0)
	check(not torch.shadow_enabled, "low-budget tiers can disable the torch shadow")
	app.queue_free()
	await _frames(2)


func test_daylight_and_glow() -> void:
	var model := (load(CampusData.scene_path("teach1")) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var light := CampusLighting.new()
	light.options = GraphicsProfile.preset(4)
	root.add_child(light)
	light.setup("teach1", CampusData.layout("teach1"), model, 0)
	check(light.find_children("*", "SpotLight3D", true, false).is_empty(), "even the highest tier has no window projectors or per-window light nodes")
	light.update(0, 700, null)
	var day := light.env.ambient_light_energy
	light.update(0, 1380, null)
	check(light.env.ambient_light_energy < day * .1, "removing window projections keeps daytime/nighttime contrast")
	light.blackout = true
	light.update(0, 700, null)
	check(light.room_lights.all(func(l: OmniLight3D) -> bool: return is_zero_approx(l.light_energy)), "blackout still extinguishes every lamp")
	light.rebind_model(model)
	check(light.find_children("*", "SpotLight3D", true, false).is_empty() and not light.env.glow_enabled, "model changes cannot recreate window projections or bloom")
	light.queue_free()
	model.queue_free()
	await _frames(1)
	CampusData.clear_caches()


func test_talent_effects() -> void:
	var app := APP.instantiate() as GameApp
	app.settings = GameSettings.new(_test_path.get_base_dir() + "/talent-effects.json")
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var world := CampusWorld.new()
	world.scene_id = GarageModule.ROOM
	root.add_child(world)
	app.session = SessionFactory.create()
	app.session.start(GarageModule.ROOM)
	app.ui.set_mode("play")

	app.garage().car_right = "12:4"
	app.talent().pick("drive")
	app._present_car_highlight(world)
	var outline := world._correct_car_outline
	var at := CampusGeometry.to_scene(world.layout, CampusGeometry.tile_center(world.layout, 12, 4))
	check(is_instance_valid(outline) and outline.get_child_count() > 0 and outline.get_children().all(
		func(part: MeshInstance3D) -> bool: return Vector2(part.position.x, part.position.z).is_equal_approx(at)),
		"the highlight covers only the actual vehicle meshes in the correct parking space")
	app._present_car_highlight(world, false)
	check(not is_instance_valid(outline), "the car highlight is private to an eligible viewer")

	app.talent().pick("night")
	app.school().tsec = 700.0
	app._update_campus_lighting(world, 0.0)
	check(world.lighting.night_vision_strength == 0.0, "dark adaptation is inactive in daylight")
	app.school().tsec = 1380.0
	app._update_campus_lighting(world, 0.0, false)
	var base_energy := world.lighting.env.ambient_light_energy
	app._update_campus_lighting(world, 0.0)
	check(world.lighting.env.ambient_light_energy > base_energy * 2.0
		and app.ui.scene_post()._parameters["night_vision"] == 1.0, "night vision lights the scene and enables its filter")

	app.talent().pick("ear")
	app.player.position = Vector3.ZERO
	app.player.rotation.y = PI / 2.0
	var patrol_state := app.patrol().pat
	patrol_state.merge({"state": "walk", "room": GarageModule.ROOM, "fy": 0.0, "x": world.layout.cx, "y": world.layout.cy - 135.0}, true)
	app._present_patrol(world, {}, 0.0)
	var radar := app.ui._patrol_radar
	check(world.patrol_figure_shown() and world._patrol_sensed and is_instance_valid(radar)
		and radar.visible and radar._offset.is_equal_approx(Vector3(15, 0, 0)),
		"15 m at the camera's right appears on radar and through occlusion")
	app._present_patrol(world, {}, 0.0, false)
	check(not world._patrol_sensed and not radar.visible, "a spectator does not inherit a radar contact")
	app._present_patrol(world, {}, 0.0)
	patrol_state["fy"] = 1.0
	app._present_patrol(world, {}, 0.0)
	check(not world.patrol_figure_shown() and not world._patrol_sensed and not radar.visible,
		"crossing the 3D range limit hides both the silhouette and its radar contact")

	world.queue_free()
	app.queue_free()
	await _frames(2)


func test_scene_materials() -> void:
	var model := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(.2, .4, .6, .35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(.3, .2, .1)
	glass.metallic = .7
	mesh.mesh.surface_set_material(0, glass)
	model.add_child(mesh)
	var original := mesh.mesh
	check(SceneMaterials.apply(model, 4) == 1, "high-tier PBR is replaced by diffuse lighting")
	for q in 5:
		check(SceneMaterials.apply(model, q) == 0 and glass.specular_mode == BaseMaterial3D.SPECULAR_DISABLED and glass.diffuse_mode == BaseMaterial3D.DIFFUSE_LAMBERT and glass.metallic == 0,
			"all tiers share an idempotent inexpensive surface response")
	check(glass.albedo_color == Color(.2,.4,.6,.35) and glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.emission == Color(.3,.2,.1) and mesh.mesh == original,
		"matte lighting preserves glass transparency, colour, emission and geometry")
	model.free()
	# Preview models have independent material resources. A quality edit must reach
	# neighbours through every connection, including a live stair shaft and gallery.
	var world := CampusWorld.new()
	var materials: Array[StandardMaterial3D] = []
	for kind: String in ["Model", "link", "stair", "door", "shaft", "gallery"]:
		var preview := Node3D.new()
		preview.name = kind
		var part := MeshInstance3D.new()
		part.mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.resource_name = "MeshPhongMaterial"
		material.roughness = 0.6
		part.mesh.surface_set_material(0, material)
		materials.append(material)
		preview.add_child(part)
		world.add_child(preview)
		match kind:
			"link": world.link_previews.append(preview)
			"stair": world.stair_previews.append(preview)
			"door": world.door_previews.append(preview)
			"shaft": world._shaft_levels[0] = preview
			"gallery": world.gallery_campus = preview
	var keep_quality := CampusLighting.quality
	CampusLighting.quality = 2
	world.apply_material_quality()
	check(materials.all(func(material: StandardMaterial3D) -> bool: return is_equal_approx(material.roughness, SceneMaterials.MATTE)), "quality changes update room, links, stairs, doors, shafts and gallery materials")
	CampusLighting.quality = 0
	world.apply_material_quality()
	check(materials.all(func(material: StandardMaterial3D) -> bool: return is_equal_approx(material.roughness, SceneMaterials.MATTE)), "changing clarity never reintroduces PBR in a neighbouring view")
	CampusLighting.quality = keep_quality
	world.free()


func test_rain_buffers() -> void:
	for q in [0, 2, 4]:
		var rain := WeatherFx.new()
		root.add_child(rain)
		rain.setup_rain(Vector3(150, 4, 220), q)
		var rid := rain._mesh.get_rid()
		for frame in 3:
			var camera := Vector3(150 + frame, 5.65, 220 - frame)
			rain.update_rain(.016, camera, 4)
			check(rain._mesh.get_rid() == rid and rain._mesh.get_surface_count() == 1, "rain reuses one mesh/surface across movement")
			check(rain._lines.position == Vector3(camera.x,4,camera.z) and Array(rain._vertices).all(func(p: Vector3) -> bool: return rain._lines.custom_aabb.has_point(p)), "rain bounds follow the player away from the world origin")
			if DisplayServer.get_name() != "headless":
				var uploaded: PackedVector3Array = rain._mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				check(uploaded == rain._vertices, "the actual Vulkan vertex buffer contains this frame's rain")
		check(rain._seeds.size() <= 1000 and rain._rings.all(func(n: MeshInstance3D) -> bool: return n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and rain._puddles.all(func(n: MeshInstance3D) -> bool: return n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "rain detail stays bounded and translucent splashes never cast solid shadows")
		var ring := rain._rings[0].mesh as TorusMesh
		check(ring.rings * ring.ring_segments <= 48, "subpixel splashes do not use thousands of triangles")
		rain.free()
