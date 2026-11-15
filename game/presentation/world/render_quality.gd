class_name RenderQuality
extends RefCounted
## A fixed work budget on every renderer. UI keeps native resolution; the 3D
## buffer is bounded by both short edge and pixel count on ultrawide phones.
const HEIGHTS := [480, 600, 720, 900, 1080, 0] # last: explicit native resolution
const LOD_THRESHOLD := [4.0, 2.0, 1.0]


static func resolution(size: Vector2i, options: Dictionary) -> Dictionary:
	var scale := clampf(float(options.get("render_scale", 100)) / 100.0, .5, 1.0)
	var edge := int(HEIGHTS[clampi(int(options.get("render_budget", 2)), 0, HEIGHTS.size() - 1)])
	if edge > 0 and size.x > 0 and size.y > 0:
		var pixels := float(edge * edge) * 16.0 / 9.0
		scale = minf(scale, minf(float(edge) / mini(size.x, size.y), sqrt(pixels / (float(size.x) * size.y))))
	scale = maxf(.1, scale)
	return {"scale": scale, "size": Vector2i(maxi(1, floori(size.x * scale)), maxi(1, floori(size.y * scale))), "budget": edge}


static func apply_resolution(vp: Viewport, mobile: bool, options: Dictionary) -> Dictionary:
	var size := (vp as Window).size if vp is Window else Vector2i(vp.get_visible_rect().size)
	var result := resolution(size, options)
	vp.scaling_3d_scale = result.scale
	var fsr: bool = not mobile and bool(options.get("upscaler", 1)) and result.scale < 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = .3
	result["fsr"] = fsr
	return result


static func apply(vp: Viewport, q: int, mobile: bool, options: Dictionary = {}) -> Dictionary:
	var config := GraphicsProfile.preset(clampi(q, 0, 4)).merged(options, true)
	var result := apply_resolution(vp, mobile, config)
	vp.msaa_3d = Viewport.MSAA_2X if int(config.msaa) > 0 else Viewport.MSAA_DISABLED
	var atlas: int = [0, 1024, 2048][clampi(int(config.shadow_resolution), 0, 2)]
	vp.positional_shadow_atlas_size = atlas
	vp.positional_shadow_atlas_16_bits = true
	vp.mesh_lod_threshold = float(LOD_THRESHOLD[clampi(int(config.lod_detail), 0, 2)])
	vp.use_occlusion_culling = true
	# Retain the Mobile FXAA workaround for Godot 4.6.3 replay compilation.
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not mobile and int(config.fxaa) == 1 and vp.msaa_3d == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED
	if DisplayServer.get_name() != "headless":
		RenderingServer.directional_shadow_atlas_set_size(1024 if int(config.sun_shadow_detail) <= 0 else 2048, true)
		var filtering := clampi(int(config.shadow_filter), 0, 1) as RenderingServer.ShadowQuality
		RenderingServer.directional_soft_shadow_filter_set_quality(filtering)
		RenderingServer.positional_soft_shadow_filter_set_quality(filtering)
	result.merge({"atlas": atlas, "lod": vp.mesh_lod_threshold})
	return result


static func apply_frame_limit(fps: int, vsync: bool) -> void:
	Engine.max_fps = clampi(fps, 0, 360)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != mode: DisplayServer.window_set_vsync_mode(mode)


static func apply_torch(torch: SpotLight3D, q: int, options: Dictionary = {}) -> void:
	if torch == null: return
	torch.light_cull_mask = CampusLighting.WORLD_LIGHT_MASK
	torch.position = Vector3(.16, -.22, -.2)
	torch.shadow_enabled = bool(options.get("torch_shadows", q >= 2)) and int(options.get("shadow_resolution", 1)) > 0
	torch.shadow_bias = .04
	torch.shadow_normal_bias = 1.0
	torch.shadow_blur = 1.0
	torch.spot_angle_attenuation = .6
	torch.spot_attenuation = 1.1
	torch.light_volumetric_fog_energy = 0.0
