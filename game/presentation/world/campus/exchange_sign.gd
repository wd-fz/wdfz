class_name ExchangeSign
extends RefCounted
## Original bilingual reception canvas and its freestanding post.

static func make(at: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "ExchangeSign"
	root.position = Vector3(at.x,0,at.y)
	var plate := MeshInstance3D.new()
	plate.name = "Panel"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2,.75)
	plate.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/campus/exchange/exchange-sign.png")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color("#555555")
	material.emission_texture = material.albedo_texture
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	material.roughness = 1
	plate.material_override = material
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.position.y = 1.2
	root.add_child(plate)
	var post := MeshInstance3D.new()
	post.name = "Post"
	var shape := BoxMesh.new()
	shape.size = Vector3(.06,1.2,.06)
	post.mesh = shape
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#555b5e")
	metal.roughness = 1
	post.material_override = metal
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep the support behind the printed face; the old +.02 offset covered its lower text.
	post.position = Vector3(0,.6,-.04)
	root.add_child(post)
	return root
