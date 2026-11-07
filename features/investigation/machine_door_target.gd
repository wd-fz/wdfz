class_name MachineDoorTarget
extends WorldInteractable
## Spatial safety belongs to the physics adapter, not the saved door rules.

var rules: InvestigationModule
var clearance: CollisionShape3D


func blocked_reason(player: CharacterBody3D) -> String:
	if rules == null or not rules.door_open() or clearance == null:
		return ""
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance.shape
	query.transform = clearance.global_transform
	query.collision_mask = player.collision_layer
	query.collide_with_areas = false
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query):
		if hit["collider"] == player:
			return "先让开门口，再关门。"
	return ""
