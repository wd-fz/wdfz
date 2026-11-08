class_name LiftCrowdFx
extends Node
## crowd-fx.js: presentation only. The sign faces into the physical cabin.
var sign: Node3D
var key := ""
var phase := ""
var age := 0.0
var _audio: AudioFx


static func here(state: Dictionary, scene: String) -> bool:
	return not state.is_empty() and scene == String(state["host"])+str(int(state["floor"]))


static func light_mul(t: float, reduce_flash: bool) -> float:
	if reduce_flash:
		return .62+.18*cos(t*2.2)
	var ph := fposmod(t*1.1,1)
	return .3 if ph>.82 and ph<.95 else .85


static func display_face(width: float, height: float) -> MeshInstance3D:
	var face := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(width,height)
	face.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://assets/campus/crowd/full.png")
	face.material_override = material
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return face


func clear() -> void:
	_clear_sign()
	if is_instance_valid(_audio) and phase in ["full","closing"]:
		_audio.stop("threat")
	phase=""
	age=0.0


func _exit_tree() -> void:
	clear()


func _clear_sign() -> void:
	if is_instance_valid(sign):
		sign.queue_free()
	sign=null
	key=""


func update(dt: float, state: Dictionary, scene: String, world: Node3D, lift: ElevatorModule, sound: AudioFx, dead: bool, reduce_flash: bool) -> void:
	_audio=sound
	var show_sign: bool = here(state,scene) and not dead and (state["phase"]!="gone" or float(lift.lifts[state["host"]]["door"])>.05)
	if not show_sign:
		_clear_sign()
	elif not is_instance_valid(sign) or key!=scene:
		_clear_sign()
		_build(scene,world,lift)
	var next := String(state.get("phase","")) if not dead else ""
	if next!=phase:
		if next=="full" and phase=="":
			age=0.0
			_audio.play("event.liftOverload")
			_audio.play("threat.crowd",{"at":.7})
		if next in ["","gone"] and phase in ["full","closing"]:
			_audio.stop("threat")
		phase=next
	age+=dt
	if is_instance_valid(sign):
		sign.visible=reduce_flash or not (age<.5 and floori(age*8)%2==1)


func _build(scene: String, world: Node3D, lift: ElevatorModule) -> void:
	if world==null:
		return
	var frame := lift.frame(scene)
	if frame.is_empty():
		return
	var p := CampusGeometry.to_scene(CampusData.layout(scene),lift.world(scene,ElevatorModule.GEO["inner"]-.22,0))
	sign=Node3D.new()
	sign.name="LiftFullDisplay"
	# The exported car roof ends at 2.14 m (2.3 - .08 - .08).
	# Suspend the 16 cm housing below it; centering it at 2.14 buries half the text.
	sign.position=Vector3(p.x,2.06,p.y)
	var out: Vector2=frame["out"]
	sign.rotation.y=atan2(-out.x,-out.y)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size=Vector3(.3,.16,.03)
	mesh.mesh=box
	var mat := StandardMaterial3D.new()
	mat.albedo_color=Color("#22272a")
	mesh.material_override=mat
	mesh.position.z=-.017
	sign.add_child(mesh)
	var face := display_face(.26,.1)
	sign.add_child(face)
	world.add_child(sign)
	key=scene
