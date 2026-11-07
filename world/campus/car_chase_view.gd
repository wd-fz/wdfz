class_name CarChaseView
extends Node3D
## Placeholder presentation of the drive out of school (the Web version's car-chase view is not
## ported): a straight night road along -Z, the barriers at their distances and lateral positions,
## the two forks with their signs, and the camera at the driver's seat. Unlit primitives; it only
## reads the chase state.

const ROAD_W := 9.0
const EYE := 1.25

var _cam_target := Vector3.ZERO


func _ready() -> void:
	var length := CarChaseRules.DISTANCE + 60.0
	_box(Vector3(0, -0.05, -length * 0.5 + 20.0), Vector3(ROAD_W, 0.1, length + 40.0), Color(0.12, 0.12, 0.13))
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (ROAD_W * 0.5 + 6.0), -0.06, -length * 0.5 + 20.0), Vector3(12.0, 0.1, length + 40.0), Color(0.05, 0.07, 0.05))
	var z := 0.0
	while z < length:
		_box(Vector3(0, 0.01, -z), Vector3(0.15, 0.02, 2.0), Color(0.85, 0.85, 0.8))
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * (ROAD_W * 0.5 + 0.3), 0.6, -z), Vector3(0.12, 1.2, 0.12), Color(0.8, 0.8, 0.75))
		z += 8.0
	for o: Array in CarChaseRules.OBSTACLES:
		_box(Vector3(float(o[1]), 0.5, -float(o[0])), Vector3(2.2, 1.0, 0.5), Color(0.95, 0.45, 0.1))
		_box(Vector3(float(o[1]), 0.75, -float(o[0]) + 0.26), Vector3(2.2, 0.18, 0.02), Color(0.95, 0.95, 0.9))
	for f: Array in CarChaseRules.FORKS:
		var right := int(f[1]) > 0
		for side: int in [-1, 1]:
			var good: bool = (side > 0) == right
			var sign := Label3D.new()
			sign.text = ("出城 →" if side > 0 else "← 出城") if good else ("回校 →" if side > 0 else "← 回校")
			sign.font_size = 96
			sign.pixel_size = 0.012
			sign.modulate = Color(0.95, 0.95, 0.9) if good else Color(0.95, 0.75, 0.7)
			sign.shaded = false
			sign.position = Vector3(side * 3.0, 2.6, -float(f[0]) + 25.0)
			add_child(sign)
	var finish := Label3D.new()
	finish.text = "武大附中 →  （已离开）"
	finish.font_size = 96
	finish.pixel_size = 0.014
	finish.shaded = false
	finish.position = Vector3(0, 3.0, -CarChaseRules.DISTANCE - 8.0)
	add_child(finish)
	var lamp := SpotLight3D.new()
	lamp.name = "Headlights"
	lamp.spot_range = 45.0
	lamp.spot_angle = 28.0
	lamp.light_energy = 3.0
	add_child(lamp)


func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Where the driver's eye is for this chase state (local to this node).
static func eye(d: Dictionary) -> Vector3:
	return Vector3(float(d["x"]), EYE, -float(d["distance"]))


func update(d: Dictionary) -> void:
	var lamp := get_node("Headlights") as SpotLight3D
	lamp.position = eye(d) + Vector3(0, -0.3, -0.5)
