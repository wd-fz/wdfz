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
static func make(kind: String, color: Color, unlit: bool = false, scale: float = 1.0, emission: Color = Color.BLACK, fog_enabled: bool = true, flat_shadow: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Figure_" + kind
	if not available(kind):
		return root
	# A projected window silhouette is a fixed shape, not a standing 3D character.
	# Keep its original outline while ordinary and uncanny people use the new mesh.
	var key := "window_shadow" if flat_shadow and kind == "person" else kind
	if not _cache.has(key):
		_cache[key] = load("res://assets/campus/figures/%s.glb" % key)
	var inst := (_cache[key] as PackedScene).instantiate() as Node3D
	inst.rotation.y = PI
	root.add_child(inst)
	var mat := StandardMaterial3D.new()
	# Original figMesh callers tint the whole person; they do not enable vertexColors.
	# The exported asset carries baked vertex shades for other uses, which must not darken this tint.
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.emission_enabled = emission != Color.BLACK
	mat.emission = emission
	mat.disable_fog = not fog_enabled
	if unlit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unlit else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.scale = Vector3.ONE * scale
	return root


## The dressed variant of a kind (tools/remodel/dress.py): the same body with clothes laid over it, one
## mesh per garment named "dressed_<kind>_<garment>" (skin, jacket, trim, zip, trousers, shoes, shirt). Only the
## death stages use it, for close shots; people in the campus keep the plain figure. null when missing.
const DRESSED := ["person", "sit", "teacher", "roam"]

static func dressed(kind: String) -> PackedScene:
	var path := "res://assets/campus/figures/dressed/%s.glb" % kind
	if not DRESSED.has(kind) or not ResourceLoader.exists(path): return null
	var key := "dressed|" + kind
	if not _cache.has(key): _cache[key] = load(path)
	return _cache[key]


## The standing height of a kind in metres (hip + torso + neck + head, from FIG_SPEC).
static func height(kind: String) -> float:
	return {"tall": 2.55, "roam": 2.63, "person": 1.85, "teacher": 2.49, "neck": 2.96, "sit": 1.35}.get(kind, 1.8)
