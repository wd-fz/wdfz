class_name GraphicsProfile
extends RefCounted
## Presets are shortcuts which populate independent rendering controls. Frame pacing
## and comfort preferences deliberately survive preset changes. No gameplay settings.
const CUSTOM := 5
const PRESETS := {
	"render_scale": [55,70,100,100,100], "model_detail": [0,1,2,3,4],
	"lighting_detail": [0,1,2,3,4], "particle_detail": [0,1,2,3,4],
	"upscaler": [1,1,0,0,0], "msaa": [0,0,0,2,3], "fxaa": [0,0,1,1,1],
	"lod_detail": [0,1,2,2,3], "sun_shadows": [0,0,1,1,1],
	"sun_shadow_detail": [0,0,1,2,2], "shadow_resolution": [0,0,2,3,3],
	"shadow_filter": [0,0,2,3,4], "lamp_shadows": [0,0,1,2,4],
	"window_shadows": [0,0,1,2,4], "torch_shadows": [0,0,1,1,1],
	"window_light": [0,0,1,1,1], "ssao": [0,0,1,2,3], "ssao_half": [1,1,1,0,0],
	"glow": [0,1,1,1,1], "volumetric_fog": [0,0,0,0,1],
	"post_detail": [0,1,1,1,1], "bloom": [0,0,0,0,32], "grain_strength": [100,100,100,100,60],
}
const FRAME_KEYS := ["fps_limit","vsync"]

static func preset(tier: int) -> Dictionary:
	var result := {}
	for key: String in PRESETS: result[key]=PRESETS[key][clampi(tier,0,4)]
	return result

static func from_values(values: Dictionary) -> Dictionary:
	var result := preset(int(values.get("quality",2)) if int(values.get("quality",2))<CUSTOM else 2)
	for key: String in PRESETS:
		if values.has(key): result[key]=values[key]
	return result
