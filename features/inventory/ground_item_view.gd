class_name GroundItemView
extends Node3D
## Rebuilt from rule state, including after loading. No item awards in this view.

var _inventory: InventoryModule
var _world_id := ""


func bind_rules(inventory: InventoryModule, world_id: String) -> void:
	clear()
	_inventory = inventory
	_world_id = world_id
	_inventory.changed.connect(_rebuild)
	_rebuild()


func clear() -> void:
	if _inventory != null and _inventory.changed.is_connected(_rebuild):
		_inventory.changed.disconnect(_rebuild)
	_inventory = null
	_remove_children()


func _remove_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _rebuild() -> void:
	_remove_children()
	var ground := _inventory.dropped_in(_world_id)
	var index := 0
	for id: String in ground:
		var record: Dictionary = ground[id]
		var coordinates: Array = record["position"]
		var body := WorldInteractable.new()
		body.interaction_id = StringName("inventory.pickup." + id)
		body.prompt = "拾取「%s」" % _inventory.details(id)["name"]
		body.collision_layer = 8 # Non-blocking pickups; still occluded by world walls.
		body.collision_mask = 0
		body.position = Vector3(coordinates[0], coordinates[1] + 0.18, coordinates[2]) + Vector3((index % 3 - 1) * 0.12, 0, (index / 3) * 0.12)
		var mesh := MeshInstance3D.new()
		var geometry := SphereMesh.new()
		geometry.radius = 0.12
		geometry.height = 0.24
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.85, 0.69, 0.34) if id == "roomkey" else Color(0.7, 0.8, 0.8)
		geometry.material = material
		mesh.mesh = geometry
		body.add_child(mesh)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.18
		collision.shape = shape
		body.add_child(collision)
		var label := Label3D.new()
		label.text = _inventory.details(id)["name"]
		label.position.y = 0.35
		label.pixel_size = 0.004
		label.font_size = 28
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		body.add_child(label)
		add_child(body)
		index += 1


func _exit_tree() -> void:
	if _inventory != null and _inventory.changed.is_connected(_rebuild):
		_inventory.changed.disconnect(_rebuild)
	_inventory = null
