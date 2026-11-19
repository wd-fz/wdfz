class_name AnomalyWriting
extends MeshInstance3D
## The forecast comes from the event. A blank board has no invented time.
const SHADER := preload("res://game/presentation/world/campus/anomaly_writing.gdshader")
const INK := preload("res://assets/campus/anomalies/writing/writing-ink.png")
const BOARD := preload("res://assets/campus/anomalies/writing/blackboard.webp")
const PAPER := preload("res://assets/campus/anomalies/writing/register.webp")
var surface := ShaderMaterial.new()
var register_sheet := false
var forecast := false


func build(kind: String, data: Dictionary, student: String) -> void:
	register_sheet = kind == "roster"
	forecast = not register_sheet and data.has("until")
	var quad := QuadMesh.new()
	quad.size = Vector2(.90,1.20) if register_sheet else Vector2(2.92,1.16)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.shader = SHADER
	surface.set_shader_parameter("sheet", PAPER if register_sheet else BOARD)
	surface.set_shader_parameter("ink", INK)
	surface.set_shader_parameter("register_sheet", register_sheet)
	surface.set_shader_parameter("student_row", float(StudentCast.IDS.find(StudentCast.resolve(student))))
	surface.set_shader_parameter("forecast", forecast)
	if forecast:
		var clock := SchoolClock.fmt_clock(float(data.until))
		surface.set_shader_parameter("clock_digits",Vector4(clock.substr(0,1).to_int(),clock.substr(1,1).to_int(),clock.substr(3,1).to_int(),clock.substr(4,1).to_int()))
	material_override = surface


func write_at(seconds: float) -> void:
	surface.set_shader_parameter("written", smoothstep(.45,2.85,seconds) if register_sheet else smoothstep(.25,4.2,seconds))
	if not register_sheet and not forecast: surface.set_shader_parameter("erased",smoothstep(7.0,12.0,seconds))
