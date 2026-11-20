class_name GameSettings
extends RefCounted
## Player settings, ported from the Web version (reference wd-fz.github.io@0bf508a, settings.js and
## quality.js). Presentation and comfort only: no setting changes the rules, the collision or the
## timetable. Saved on its own (user://settings.json), never inside a run's save.
##
## vol 0–100 (default 70) · amb 1/0 ambient layers · captions 0 auto / 1 on / 2 off (default on) ·
## sub 0/1/2 caption size · distortion 0 off / 1 reduced / 2 full · reduce_flash 1/0 · bright 50–150 ·
## grain 1/0 · mouse, touch 25–250 look sensitivity % · text 85–150 % · touch_size 85–125 % ·
## quality 0–4 presets / 5 custom; GraphicsProfile expands independent parameters.
## fps_limit 0 unlimited / 20–360. VSync is independent. menu_orbit 1/0 selects the baked campus panorama
## or the rainy campus cover. auto_land rotates between landscape sides only.
## Desktop defaults to windowed. Android and iOS use fullscreen.
## The Web "graphics mode" (WebGL / WebGPU) is replaced by Godot's renderer. Touch layout is
## stored separately from numeric settings and from gameplay saves.

const VERSION := 4
const DEFAULTS := {"vol": 70, "amb": 1, "captions": 1, "sub": 1, "distortion": 2, "reduce_flash": 0, "bright": 100, "grain": 1,
	"mouse": 100, "touch": 100, "text": 100, "touch_size": 100, "quality": 2, "auto_land": 1, "full_screen": 0, "shake": 1,
	"fps_limit":60, "vsync":1, "render_scale":100, "render_budget":2, "model_detail":2, "lighting_detail":2,
	"particle_detail":2, "upscaler":1, "msaa":0, "fxaa":1, "lod_detail":1,
	"sun_shadows":1, "sun_shadow_detail":0, "shadow_resolution":1, "shadow_filter":1,
	"torch_shadows":1, "post_detail":1, "grain_strength":100, "menu_orbit":0}
const LIMITS := {"vol": [0,100], "bright": [50,150], "mouse": [25,250], "touch": [25,250], "text": [85,150], "touch_size": [85,125],
	"fps_limit":[0,360], "render_scale":[50,100], "grain_strength":[0,100]}
const CHOICES := {"amb":2, "captions":3, "sub":3, "distortion":3, "reduce_flash":2, "grain":2, "quality":6, "auto_land":2, "full_screen":2, "shake":2,
	"vsync":2, "render_budget":6, "model_detail":4, "lighting_detail":5, "particle_detail":5, "upscaler":2,
	"msaa":2, "fxaa":2, "lod_detail":3, "sun_shadows":2, "sun_shadow_detail":2,
	"shadow_resolution":3, "shadow_filter":2, "torch_shadows":2, "post_detail":2, "menu_orbit":2}
const QUALITY_LABELS := ["流畅", "均衡", "精细", "高清", "极清", "自定义"]
## Compatibility helpers for UI/tests. RenderQuality applies the actual pixel budget;
## no preset supersamples or requests more than 2x MSAA.
const QUALITY_SCALE := [1.0, 1.0, 1.0, 1.0, 1.0]
const QUALITY_MSAA := [0, 0, 0, 1, 1]
## Default 精细 (2) retains tier-2 geometry; higher tiers do not add physical-lighting passes.
const QUALITY_SHADOW := [false, false, true, true, true]
const SUB_MULT := [0.6, 1.0, 1.6]

var path: String
var platform: String
var values: Dictionary = DEFAULTS.duplicate()
var touch_layout: Dictionary = {}
## action -> [key, key] (KeyBindings); applied to the InputMap by apply_bindings().
var bindings: Dictionary = KeyBindings.defaults()
var wuda_armed := false  # local menu unlock, not a visible setting or a chosen talent
var rules_armed := false # bundled DLC selection applies to subsequent new runs only


func _init(file: String = "user://settings.json", platform_name: String = OS.get_name()) -> void:
	path = file
	platform = platform_name
	_enforce_platform()


static func can_toggle_fullscreen(platform_name: String = OS.get_name()) -> bool:
	return platform_name not in ["Android", "iOS"]


func _enforce_platform() -> void:
	if not can_toggle_fullscreen(platform): values["full_screen"] = 1


## Clamp or default every entry; unknown keys are dropped.
static func normalize(raw: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate()
	var tier: Variant=raw.get("quality",2)
	if not (tier is int or tier is float) or not is_finite(float(tier)): tier=2
	tier=int(round(float(tier)))
	if tier<0 or tier>GraphicsProfile.CUSTOM: tier=2
	out.merge(GraphicsProfile.preset(tier if tier<GraphicsProfile.CUSTOM else 2),true)
	for k: String in DEFAULTS:
		if not raw.has(k) or not (raw[k] is int or raw[k] is float):
			continue
		if not is_finite(float(raw[k])): continue
		var v := int(round(float(raw[k])))
		if LIMITS.has(k):
			out[k] = clampi(v, int(LIMITS[k][0]), int(LIMITS[k][1]))
		elif CHOICES.has(k):
			out[k] = v if v >= 0 and v < int(CHOICES[k]) else out[k]
	if out.fps_limit>0: out.fps_limit=maxi(20,out.fps_limit)
	if int(out.quality)<GraphicsProfile.CUSTOM:
		var preset:=GraphicsProfile.preset(out.quality)
		for key: String in preset:
			if out[key]!=preset[key]: out.quality=GraphicsProfile.CUSTOM; break
	return out


## First run on a touch device: performance first (quality 流畅), as the Web version did.
func load_file(touch_device: bool = false) -> bool:
	touch_layout = {}
	bindings = KeyBindings.defaults()
	wuda_armed=false
	rules_armed=false
	if not FileAccess.file_exists(path):
		values = DEFAULTS.duplicate()
		if touch_device:
			set_value("quality",0)
		_enforce_platform()
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	wuda_armed = parsed is Dictionary and parsed.get("wuda_armed") is bool and parsed["wuda_armed"]
	rules_armed = parsed is Dictionary and parsed.get("rules_armed") is bool and parsed["rules_armed"]
	var version: Variant = parsed.get("version", 0) if parsed is Dictionary else 0
	if not (version is int or version is float) or not is_finite(float(version)): version = 0
	var raw: Dictionary = parsed.get("values", {}) if parsed is Dictionary and parsed.get("values") is Dictionary else {}
	if int(version) < 4:
		raw = raw.duplicate()
		# An old preset adopts its replacement budget; custom profiles retain supported
		# choices, clamped below. Retired effects are dropped by normalize().
		var tier: Variant = raw.get("quality", 2)
		if (tier is int or tier is float) and is_finite(float(tier)) and int(tier) in range(5):
			raw.merge(GraphicsProfile.preset(int(tier)), true)
		for key: String in ["msaa", "model_detail", "lod_detail", "sun_shadow_detail", "shadow_resolution", "shadow_filter"]:
			if raw.get(key) is int or raw.get(key) is float:
				if is_finite(float(raw[key])): raw[key] = clampi(int(raw[key]), 0, int(CHOICES[key]) - 1)
		# Version 3 defaulted to unlimited, which drives 120/144 Hz phones continuously.
		# Apply the new 60 FPS default once; version 4 still accepts an explicit unlimited choice.
		if raw.get("fps_limit", 0) == 0: raw["fps_limit"] = 60
	values = normalize(raw)
	_enforce_platform()
	touch_layout = TouchLayout.normalize(parsed.get("touch_layout", {}) if parsed is Dictionary else {})
	bindings = KeyBindings.normalize(parsed.get("bindings", {}) if parsed is Dictionary else {})
	return parsed is Dictionary


func save_file() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": VERSION, "values": values, "touch_layout": touch_layout, "bindings": bindings,"wuda_armed":wuda_armed,"rules_armed":rules_armed}))
	file.close()
	return true


func get_int(key: String) -> int:
	if key == "full_screen" and not can_toggle_fullscreen(platform): return 1
	return int(values.get(key, DEFAULTS.get(key, 0)))


## Returns the stored (normalized) value.
func set_value(key: String, value: float) -> int:
	if not DEFAULTS.has(key):
		return 0
	var next := normalize({key: value})
	var changed: bool=values[key]!=next[key]
	values[key] = next[key]
	if key=="quality" and values.quality<GraphicsProfile.CUSTOM:
		values.merge(GraphicsProfile.preset(values.quality),true)
	elif changed and GraphicsProfile.PRESETS.has(key): values.quality=GraphicsProfile.CUSTOM
	_enforce_platform()
	return int(values[key])


func graphics() -> Dictionary:
	return GraphicsProfile.from_values(values)


func reset_comfort() -> void:
	touch_layout = {}
	for k: String in ["mouse", "touch", "text", "touch_size"]:
		values[k] = DEFAULTS[k]


## Push the key bindings into the InputMap: keyboard events of the listed actions are replaced, everything else
## (touch, mouse, other actions) is left alone. Missing actions are created.
func apply_bindings() -> void:
	for id: String in bindings:
		if not InputMap.has_action(id):
			InputMap.add_action(id, 0.2)
		for ev: InputEvent in InputMap.action_get_events(id):
			if ev is InputEventKey:
				InputMap.action_erase_event(id, ev)
		for k: int in bindings[id]:
			if k == 0: continue
			var ev := InputEventKey.new()
			ev.physical_keycode = k as Key
			InputMap.action_add_event(id, ev)


## The key names of an action for hints ("E", "W / ↑"); empty when unbound.
func key_text(action: String) -> String:
	var out: PackedStringArray = []
	for k: int in bindings.get(action, []):
		if k != 0: out.append(KeyBindings.key_name(k))
	return " / ".join(out)
