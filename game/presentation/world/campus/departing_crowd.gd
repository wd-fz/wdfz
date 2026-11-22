class_name DepartingCrowd
extends Node3D
## broadcast-view.js: sixteen students in pairs, with a collision-aware centre-line fallback.
var people: Array[Node3D] = []
var _body := CylinderShape3D.new()

func _init() -> void:
	name = "DismissalCrowd"
	# Exported rectangles round to four decimals; touching an edge is free in the source.
	_body.radius = 2.7*CampusGeometry.U2M-.0001
	_body.height = 1.2
	for i in 16:
		var person := Node3D.new()
		var figure := FigureModel.make("person",Color("303c3d"),true,1,Color.BLACK,true,false,null,true)
		figure.rotation.y = PI
		person.add_child(figure)
		var bag := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.23,.3,.1)
		bag.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("1a232b")
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		RenderMaterials.set_override(bag, mat)
		bag.position = Vector3(0,1.1,-.15)
		bag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		person.add_child(bag)
		add_child(person)
		people.append(person)

func blocked(p: Vector2) -> bool:
	var at := CampusGeometry.to_scene(null,p)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _body
	query.collision_mask = 1
	query.transform = Transform3D(Basis(),Vector3(at.x,.9,at.y))
	return not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

## Keep the original two lanes where they fit. At a wide obstruction both the
## normal lane and its centre-line fallback can run through the same pillar.
func _free_slot(centre: Vector2, side: Vector2, solid: Callable) -> Vector2:
	for width: float in [1.0, 0.0, 2.0, -1.0, -2.0, 3.0, -3.0]:
		var slot := centre + side * width
		if not solid.call(slot): return slot
	return Vector2.INF

func update(crowd: Dictionary, collides: Callable = Callable()) -> void:
	if crowd.is_empty():
		hide()
		return
	show()
	var angle := float(crowd["angle"])
	var direction := Vector2(cos(angle),sin(angle))
	var origin := Vector2(crowd["x"],crowd["y"])
	var solid := collides if collides.is_valid() else blocked
	for i in people.size():
		var behind := floorf(i/2.0)*5.5
		var side := (1 if i%2 else -1)*3.1
		var p := _free_slot(origin-direction*behind, Vector2(-direction.y,direction.x)*side, solid)
		people[i].visible = p.is_finite()
		if not p.is_finite(): continue
		var at := CampusGeometry.to_scene(null,p)
		var next := Vector3(at.x,.015*sin((60-float(crowd["left"]))*6+i),at.y)
		var previous := Vector2(people[i].position.x, people[i].position.z)
		FigureGait.step(people[i].get_child(0), previous.distance_to(at), get_physics_process_delta_time())
		people[i].position = next
		people[i].rotation.y = PI/2-angle
