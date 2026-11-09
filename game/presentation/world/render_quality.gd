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


static func apply(vp: Viewport, q: int, mobile: bool) -> Dictionary:
	q = clampi(q, 0, 4)
	var use_fsr := not mobile and bool(UPSCALE_FSR[q])
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if use_fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = float(FSR_SHARPNESS[q])
	vp.positional_shadow_atlas_size = int(POSITIONAL_ATLAS[q])
	vp.positional_shadow_atlas_16_bits = true
	vp.mesh_lod_threshold = float(LOD_THRESHOLD[q])
	# Godot 4.6.3 Mobile + FXAA stalls when rendering the misread archive replay
	# (reproduced on Vulkan Lavapipe). Keep FXAA on Forward+ only until that path
	# is verified again. Both renderers retain the higher tiers' 4× / 8× MSAA.
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if not mobile and int(SCREEN_AA[q]) == 1 and vp.msaa_3d == Viewport.MSAA_DISABLED else Viewport.SCREEN_SPACE_AA_DISABLED
	if DisplayServer.get_name() != "headless":
		RenderingServer.directional_shadow_atlas_set_size(int(DIRECTIONAL_ATLAS[q]), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(int(SHADOW_FILTER[q]) as RenderingServer.ShadowQuality)
		RenderingServer.positional_soft_shadow_filter_set_quality(int(SHADOW_FILTER[q]) as RenderingServer.ShadowQuality)
		if not mobile:
			RenderingServer.environment_set_ssao_quality(int(SSAO_QUALITY[q]) as RenderingServer.EnvironmentSSAOQuality, q < 3, 0.5, 2, 50.0, 300.0)
	return {"fsr": use_fsr, "atlas": int(POSITIONAL_ATLAS[q]), "lod": float(LOD_THRESHOLD[q])}
