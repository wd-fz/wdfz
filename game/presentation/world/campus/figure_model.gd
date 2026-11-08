class_name FigureModel
extends RefCounted
## The old build's human figure (model/figure.js figMesh), exported by tools/export_scenes (--only figures):
## head, neck, torso, arms with hands, legs, shoes. Feet at y = 0, front towards -z (Godot's forward; the old build faced +z, turned here). Kinds: tall (the figure
## in an anomaly, about 2.5 m), roam (the one in the garage), person (an ordinary passer-by), teacher,
## neck (the wrong neck over the fence), sit (seated, hands on the desk).

const KINDS := ["tall", "roam", "person", "teacher", "neck", "sit"]
static var _cache: Dictionary = {}


static func available(kind: String) -> bool:
	return KINDS.has(kind) and ResourceLoader.exists("res://assets/campus/figures/%s.glb" % kind)


## A figure of the kind, tinted; scale multiplies the old size (1 = as built). unlit = the dark, unlit
## silhouette used by the anomalies. Returns an empty Node3D when the model is missing.
static func make(kind: String, color: Color, unlit: bool = false, scale: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Figure_" + kind
	if not available(kind):
		return root
	if not _cache.has(kind):
		_cache[kind] = load("res://assets/campus/figures/%s.glb" % kind)
	var inst := (_cache[kind] as PackedScene).instantiate() as Node3D
	inst.rotation.y = PI
	root.add_child(inst)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.roughness = 1.0
	if unlit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unlit else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.scale = Vector3.ONE * scale
	return root


## The standing height of a kind in metres (hip + torso + neck + head, from FIG_SPEC).
static func height(kind: String) -> float:
	return {"tall": 2.55, "roam": 2.63, "person": 1.85, "teacher": 2.49, "neck": 2.96, "sit": 1.35}.get(kind, 1.8)
