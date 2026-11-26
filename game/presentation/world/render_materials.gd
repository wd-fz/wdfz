class_name RenderMaterials
extends RefCounted
## Godot 4.6's GeometryInstance3D setter releases its old Ref before updating the
## RenderingServer instance. Keep it alive until that update has been submitted,
## so an immediate dependency refresh cannot inspect an already freed material.


## The ordinary school uniforms, skin and hair share one authored vertex-colour material.
static func apply_character_palette(mesh: Mesh) -> void:
	if mesh == null: return
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material != null and material.resource_name == "CampusCloth" and not material.vertex_color_use_as_albedo:
			material.vertex_color_use_as_albedo = true


static func set_override(instance: GeometryInstance3D, material: Material) -> void:
	var previous := instance.material_override
	if previous == material: return
	instance.material_override = material
	# Release after the setter, without a GPU flush or retaining resources across frames.
	previous = null


static func set_surface_override(instance: MeshInstance3D, surface: int, material: Material) -> void:
	var previous := instance.get_surface_override_material(surface)
	if previous == material: return
	instance.set_surface_override_material(surface, material)
	previous = null
