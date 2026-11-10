class_name ScenePost
extends ColorRect
## One screen pass below the interface. Godot's SDR scene is decoded to linear
## light, then the original Three.js post curve is applied once. No gameplay state.

var world_normal := 0.0
var fake_normal := 0.0
var sensory_active := false
var grain := true
var quality := 1
var render_options: Dictionary = {}
var clock := 0.0
var gaze_level := 0.0
const GRADE_SHADER := preload("res://game/presentation/world/scene_post.gdshader")
const BLUR_SHADER := preload("res://game/presentation/world/scene_post_blur.gdshader")
var _parameters: Dictionary = {}
var _mipmaps := false

func _init() -> void:
	name = "ScenePost"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = GRADE_SHADER
	material = mat

func parameter(key: String, value: Variant) -> void:
	if _parameters.has(key) and _parameters[key] == value: return
	_parameters[key] = value
	(material as ShaderMaterial).set_shader_parameter(key,value)
	if key in ["blur", "focus", "normal"]:
		var radius := (13.0 * float(_parameters.get("blur",0.0)) + 4.5 * float(_parameters.get("focus",0.0))) * (1.0-float(_parameters.get("normal",0.0)))
		var needs_mips := radius >= .3
		if needs_mips != _mipmaps:
			_mipmaps = needs_mips
			var mat := material as ShaderMaterial
			mat.shader = BLUR_SHADER if _mipmaps else GRADE_SHADER
			for name: String in _parameters: mat.set_shader_parameter(name,_parameters[name])

func reset() -> void:
	world_normal = 0.0
	fake_normal = 0.0
	clock = 0.0
	gaze_level = 0.0
	sensory({},0.0,0.0)
	for key: String in ["normal","gaze","red","hurt"]:
		parameter(key,0.0)
	parameter("exposure",1.0)
	parameter("san",1.0)

func normal() -> float:
	return maxf(world_normal,fake_normal)

func step(dt: float, fake: bool, san: float) -> void:
	fake_normal += ((1.0 if fake else 0.0)-fake_normal)*minf(1.0,dt*1.6)
	parameter("normal",normal())
	parameter("san",clampf(san/100.0,0.0,1.0))

func sensory(v: Dictionary, blink: float, t: float) -> void:
	sensory_active = float(v.get("tunnel",0.0))>.01 or blink>0 or float(v.get("halo",0.0))>.01 or float(v.get("ghost_env",0.0))>.01
	for key: String in ["tunnel","blur","focus","drain","warp","halo"]:
		parameter(key,float(v.get(key,0.0)))
	parameter("breath",float(v.get("inhale",0.0)))
	parameter("pulse",float(v.get("pulse_env",0.0)))
	parameter("ghost",float(v.get("ghost_env",0.0)))
	var direction: Array = v.get("ghost_dir",[1.0,0.0])
	parameter("ghost_dir",Vector2(direction[0],direction[1]))
	parameter("blink",blink)
	clock=t
	parameter("t",clock)

func tick(dt: float) -> void:
	clock+=dt
	parameter("t",clock)
	parameter("grain",(1.0 if grain else 0.0)*float(render_options.get("grain_strength",60 if quality==4 else 100))/100.0)
	parameter("lite",int(render_options.get("post_detail",0 if quality==0 else 1))==0)
	parameter("bloom",float(render_options.get("bloom",32 if quality==4 else 0))/100.0)
