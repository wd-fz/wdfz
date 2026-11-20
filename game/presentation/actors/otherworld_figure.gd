class_name OtherworldFigure
extends Node3D
## The campus actors face -Z. Their feet and routes belong to the simulation;
## their necks, expressions and uniforms belong to this presentation.
const DIRECTORY := "res://assets/campus/figures/otherworld/%s.glb"
const SKIN := preload("res://game/presentation/actors/otherworld_cloth.gdshader")
const PROPORTIONS := {"sit":Vector3(1,1.04,1), "person":Vector3(1,1.04,1),
	"teacher":Vector3(1.06,1.34,1), "patroller":Vector3(1.18,1.51,1.12), "roam":Vector3(.94,1.45,1.02)}
static var _models: Dictionary = {}
static var _cloth: ShaderMaterial
var face: MeshInstance3D
var animation: AnimationPlayer
var _patrol_time := 0.0


static func make(kind: String, packed: PackedScene = null, variant: int = 0) -> OtherworldFigure:
	var actor := OtherworldFigure.new()
	var scene := _models.get(kind, packed) as PackedScene
	if scene == null or not scene.can_instantiate(): scene = CampusData.actor_scene(DIRECTORY % kind)
	var model := scene.instantiate() as Node3D if scene != null else null
	if model == null:
		actor.face = MeshInstance3D.new()
		actor.add_child(actor.face)
		return actor
	_models[kind] = scene
	model.scale = PROPORTIONS[kind]
	actor.add_child(model)
	if _cloth == null:
		_cloth = ShaderMaterial.new()
		_cloth.shader = SKIN
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		RenderMaterials.set_override(mesh, _cloth)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.face = model.find_child("Visage", true, false) as MeshInstance3D
	var alternate := model.find_child("VisageAlt",true,false) as MeshInstance3D
	if alternate != null:
		if actor.face == null or variant%2 == 1:
			if actor.face != null: actor.face.free()
			actor.face = alternate
		else: alternate.free()
	if actor.face == null:
		actor.face = MeshInstance3D.new()
		model.add_child(actor.face)
	actor.animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if actor.animation != null:
		var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if rig == null:
			actor.animation = null
			return actor
		var mount := BoneAttachment3D.new()
		rig.add_child(mount)
		mount.bone_name = "Head"
		actor.face.owner = null
		actor.face.reparent(mount, false)
		actor.face.transform = Transform3D.IDENTITY
		FigureGait.attach(actor)
	return actor


func turn_face(yaw: float, pitch: float, cant: float, dt: float) -> void:
	var target := Vector3(pitch, clampf(yaw, -1.42, 1.42), cant)
	face.rotation = face.rotation.move_toward(target, 3.8 * dt)


func patrol_pose(dt: float, distance: float, behavior: String) -> void:
	FigureGait.step(self, distance, dt)
	_patrol_time += dt
	var scan := sin(_patrol_time * .68)
	match behavior:
		"chase": turn_face(0, -.29, -.09, dt)
		"search", "investigate": turn_face(clampf(scan * 1.55, -1.1, 1.1), -.13, scan * .16, dt)
		_: turn_face(scan * .19, -.09, -.03, dt)


func exercise_pose(elapsed: float, index: int, to_player: Vector2) -> void:
	# One pupil completes the count late. The held pose exposes a separately turning head.
	var t := fposmod(elapsed - (.23 if index == 4 else 0.0), 3.4)
	if animation == null or not animation.has_animation("drill"): return
	if animation.current_animation != "drill": animation.play("drill", 0)
	animation.seek(t, true)
	var hold := smoothstep(1.48,1.84,t) * (1.0-smoothstep(2.61,3.1,t))
	face.rotation = Vector3(-.13*hold,clampf(atan2(-to_player.x,-to_player.y),-1.42,1.42)*hold,.13*hold)
