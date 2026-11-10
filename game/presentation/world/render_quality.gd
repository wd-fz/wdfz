class_name RenderQuality
extends RefCounted
## Renderer budget per picture quality (GameSettings 0–4, 流畅 … 真实). Presentation only: the same models' collision,
## the same rules. Scene lighting effects (SSAO, glow, lamp shadows) are in CampusLighting.apply_quality().

## Below full resolution Forward+ uses AMD FSR 1. Godot 4.6.3 Mobile only supports bilinear scaling.
const UPSCALE_FSR := [true, true, false, false, false]
## FSR sharpness (0 sharpest … 2 softest).
const FSR_SHARPNESS := [0.25, 0.3, 0.2, 0.2, 0.2]
## Shadow maps: positional (lamps, torch) atlas and directional (sun) atlas sizes; 0 turns positional shadows off.
const POSITIONAL_ATLAS := [0, 0, 2048, 4096, 4096]
const DIRECTIONAL_ATLAS := [1024, 1024, 2048, 4096, 4096]
## Soft-shadow filter: RenderingServer.ShadowQuality (0 hard … 5 ultra).
const SHADOW_FILTER := [0, 0, 2, 3, 4]
## SSAO cost: RenderingServer.EnvironmentSSAOQuality (0 very low … 4 ultra), half resolution below 超精细.
const SSAO_QUALITY := [0, 0, 1, 2, 3]
## Mesh LOD: a higher threshold switches to simpler imported LODs sooner (pixels of error allowed).
const LOD_THRESHOLD := [4.0, 2.0, 1.0, 1.0, 0.5]
## Screen-space reflections / antialiasing extras.
const SCREEN_AA := [0, 0, 1, 1, 1]   # Viewport.ScreenSpaceAA: 0 off, 1 FXAA (cheap edge smoothing where MSAA is off)


static func apply(vp: Viewport, q: int, mobile: bool, options: Dictionary = {}) -> Dictionary:
	q = clampi(q, 0, 4)
	if not options.is_empty():
		vp.scaling_3d_scale=float(options.get("render_scale",100))/100.0
		vp.msaa_3d=int(options.get("msaa",0)) as Viewport.MSAA
	var use_fsr := not mobile and bool(options.get("upscaler",UPSCALE_FSR[q])) and (options.is_empty() or vp.scaling_3d_scale<1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if use_fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = float(FSR_SHARPNESS[q])
	var atlas: int=int(POSITIONAL_ATLAS[q]) if options.is_empty() else [0,1024,2048,4096][int(options.shadow_resolution)]
	vp.positional_shadow_atlas_size = atlas
	vp.positional_shadow_atlas_16_bits = true
	vp.mesh_lod_threshold = float(LOD_THRESHOLD[q]) if options.is_empty() else [4.0,2.0,1.0,.5][int(options.lod_detail)]
	# CPU occlusion works with both Vulkan renderers. CampusBatches supplies only real
	# opaque wall triangles; doors, windows and collision approximations are excluded.
	vp.use_occlusion_culling = true
	# Godot 4.6.3 Mobile + FXAA stalls when rendering the misread archive replay
	# (reproduced on Vulkan Lavapipe). Keep FXAA on Forward+ only until that path
	# is verified again. Both renderers retain the higher tiers' 4× / 8× MSAA.
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not mobile and int(options.get("fxaa",SCREEN_AA[q])) == 1 and vp.msaa_3d == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED
	if DisplayServer.get_name() != "headless":
		var sun_atlas: int=int(DIRECTIONAL_ATLAS[q]) if options.is_empty() else [1024,2048,4096][int(options.sun_shadow_detail)]
		var filtering:=int(options.get("shadow_filter",SHADOW_FILTER[q]))
		RenderingServer.directional_shadow_atlas_set_size(sun_atlas, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(filtering as RenderingServer.ShadowQuality)
		RenderingServer.positional_soft_shadow_filter_set_quality(filtering as RenderingServer.ShadowQuality)
		if not mobile:
			RenderingServer.environment_set_ssao_quality(int(options.get("ssao",SSAO_QUALITY[q])) as RenderingServer.EnvironmentSSAOQuality, bool(options.get("ssao_half",q<3)), 0.5, 2, 50.0, 300.0)
	return {"fsr": use_fsr, "atlas": atlas, "lod": vp.mesh_lod_threshold}


static func apply_frame_limit(fps: int, vsync: bool) -> void:
	Engine.max_fps=clampi(fps,0,360)
	if DisplayServer.get_name()!="headless":
		var mode:=DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode()!=mode: DisplayServer.window_set_vsync_mode(mode)


static func apply_torch(torch: SpotLight3D, q: int, options: Dictionary = {}) -> void:
	if torch==null: return
	torch.light_cull_mask=CampusLighting.WORLD_LIGHT_MASK
	torch.position=Vector3(.16,-.22,-.2)
	torch.shadow_enabled=bool(options.get("torch_shadows",q>=2)) and int(options.get("shadow_resolution",2))>0
	torch.shadow_bias=.04
	torch.shadow_normal_bias=1.0
	torch.shadow_blur=1.2
	torch.spot_angle_attenuation=.6
	torch.spot_attenuation=1.1
	torch.light_volumetric_fog_energy=1.4
