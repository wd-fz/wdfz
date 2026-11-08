class_name DustPoints
extends MeshInstance3D
## Square point sprites with the original distance attenuation, updated in one vertex upload.

func setup(points: PackedVector3Array) -> void:
	var shape := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh = shape
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/presentation/world/campus/dust_points.gdshader")
	material.set_shader_parameter("dust_color",Color(Color("#303030"),.65))
	material.set_shader_parameter("point_size",.012)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	update_points(points)

func update_points(points: PackedVector3Array) -> void:
	(mesh as ArrayMesh).surface_update_vertex_region(0,0,points.to_byte_array())
	var bounds := AABB(points[0],Vector3.ZERO)
	for point in points: bounds=bounds.expand(point)
	custom_aabb = bounds.grow(1.0)
