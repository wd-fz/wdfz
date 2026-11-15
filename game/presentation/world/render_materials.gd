class_name RenderMaterials
extends RefCounted
## Godot 4.6's GeometryInstance3D setter releases its old Ref before updating the
## RenderingServer instance. Keep it alive until that update has been submitted,
## so an immediate dependency refresh cannot inspect an already freed material.


static func set_override(instance: GeometryInstance3D, material: Material) -> void:
	var previous := instance.material_override
	if previous == material: return
	instance.material_override = material
	# Release after the setter, without a GPU flush or retaining resources across frames.
	previous = null
