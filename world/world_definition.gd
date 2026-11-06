class_name WorldDefinition
extends Resource
## Trusted content registry. Save files store only world_id, never a resource path.

@export var world_id: StringName
@export var scene: PackedScene
@export var spawn_position := Vector3(0.0, 0.1, 3.0)
@export_range(-180, 180) var spawn_yaw_degrees := 0.0
@export var advances_calendar := true
## Trusted per-world settings copied onto the instantiated scene root (e.g. CampusWorld.scene_id).
@export var properties: Dictionary = {}


func spawn_pose() -> Dictionary:
	return {
		"position": [spawn_position.x, spawn_position.y, spawn_position.z],
		"yaw": deg_to_rad(spawn_yaw_degrees),
		"pitch": 0.0,
	}
