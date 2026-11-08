class_name GazeEye
extends RefCounted
## Original gazeEye sprite; the drawing already contains the red/gold iris and eyelids.

static func make(size: float, color: String) -> MeshInstance3D:
	var eye := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	eye.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/campus/anomalies/eye-"+color+".png")
	material.albedo_color.a = 0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.disable_fog = true
	material.render_priority = 5
	eye.material_override = material
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	eye.scale = Vector3(size,size*.6875,1)
	return eye
