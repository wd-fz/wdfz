class_name RulesDlcProps
extends Node3D
## Read-only original paper carriers; no collision or interaction state.
func build(spots: Array, scene: String, room: Variant) -> void:
	for spot: Dictionary in spots:
		var p: Dictionary=spot["p"]
		if p["room"]!=scene: continue
		var page:=MeshInstance3D.new()
		page.name=spot["item"]["id"]
		var shape:=QuadMesh.new()
		shape.size=Vector2(.16,.11)
		page.mesh=shape
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("f2eee2")
		material.emission_enabled=true
		material.emission=Color("3a3830")
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		page.material_override=material
		page.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		page.rotation_order=EULER_ORDER_XYZ
		if float(p["h"])<1: page.rotation=Vector3(-PI/2,0,.4)
		var xy:=CampusGeometry.to_scene(room,Vector2(p["x"],p["y"]))
		page.position=Vector3(xy.x,float(p["h"])+.012,xy.y)
		add_child(page)
