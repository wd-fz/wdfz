class_name AnomalyFx
extends Node3D
## Adapter for read-only anomaly visuals. Weather and world props own their animations;
## the module alone owns danger, damage, choices and scene lifetime.
const CUP_H := AnomalyModule.CUP_H
const COLA_H := AnomalyModule.COLA_H
var _props: Node3D
var _key := ""
var _quality := -1
var _last_t := 0.0
var _extra: Dictionary = {}
var visual_seed: int = -1
var _visual_random:=RandomNumberGenerator.new()


func _init() -> void:
	_visual_random.randomize()


func update(dt: float, an: Dictionary, room: Variant, scene: String, feet: Vector3, facing: Vector2, eye: Vector3 = Vector3.INF, hard: bool = false) -> void:
	var id:=String(an.get("id","")) if an.get("active",false) else ""
	var data: Dictionary=an.get("data",{})
	if id!="" and data.has("scene") and String(data["scene"])!=scene: id=""
	var t:=float(an.get("t",0))
	if id!=_key or _quality!=CampusData.tier or t<_last_t:
		_clear()
		_key=id
		_quality=CampusData.tier
		if id!="":
			_props=Node3D.new()
			_props.name="Anomaly_"+id
			add_child(_props)
			_build(id,data,room,feet,facing)
	_last_t=t
	if _props==null: return
	var camera_pos:=eye if eye.is_finite() else feet+Vector3(0,CameraMotion.EYE,0)
	if _extra.has("original"):
		(_extra["original"] as AnomalyProps).advance(dt,data,room,feet,float(an.get("acc",0)))
	if _extra.has("rain"): (_extra["rain"] as WeatherFx).update_rain(dt,camera_pos,feet.y)
	if _extra.has("swarm"): (_extra["swarm"] as WeatherFx).update_moths(dt,camera_pos,float(an.get("acc",0)),hard)
	if id in ["cup","cola"]: _animate_fall(id,t,data,room,feet)


func moth_nearness() -> float:
	return clampf(1.0-(_extra["swarm"] as WeatherFx).distance/12.0,0,1) if _extra.has("swarm") else 0.0


func current() -> String:
	return _key


func shown_count() -> int:
	return _props.get_child_count() if is_instance_valid(_props) else 0


func _clear() -> void:
	if is_instance_valid(_props):
		_props.hide()
		_props.queue_free()
	_props=null
	_extra={}


func _unlit(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props.add_child(mi)
	return mi


func _at(room: Variant, x: float, y: float) -> Vector2:
	return CampusGeometry.to_scene(room, Vector2(x, y))


func _build(id: String, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2) -> void:
	if id in AnomalyProps.KINDS:
		var props:=AnomalyProps.new()
		props.seed_value=visual_seed if visual_seed>=0 else _visual_random.randi()
		_props.add_child(props)
		props.build(id,d,room,feet,facing,CampusData.tier)
		_extra["original"]=props
		return
	match id:
		"rain":
			var rain:=WeatherFx.new()
			_props.add_child(rain)
			rain.setup_rain(feet)
			_extra["rain"]=rain
		"moth":
			var src: Dictionary=d.get("src",{"x":0.0,"y":0.0})
			var p:=_at(room,src["x"],src["y"])
			var swarm:=WeatherFx.new()
			_props.add_child(swarm)
			swarm.setup_moths(Vector3(p.x,feet.y,p.y))
			_extra["swarm"]=swarm
		"cup":
			var cup:=CylinderMesh.new()
			cup.top_radius=.11
			cup.bottom_radius=.085
			cup.height=.3
			_extra["obj"]=_mesh(cup,_unlit(Color(.95,.95,.97)))
			var lid:=_mesh(CylinderMesh.new(),_unlit(Color(.7,.6,.85)),Vector3(0,.16,0))
			lid.mesh.top_radius=.115
			lid.mesh.bottom_radius=.115
			lid.mesh.height=.04
			lid.get_parent().remove_child(lid)
			_extra["obj"].add_child(lid)
		"cola":
			var can:=CylinderMesh.new()
			can.top_radius=.09
			can.bottom_radius=.09
			can.height=.3
			_extra["obj"]=_mesh(can,_unlit(Color(.85,.1,.1)))


func _animate_fall(id: String, t: float, d: Dictionary, room: Variant, me: Vector3) -> void:
	var obj := _extra["obj"] as Node3D
	var h := CUP_H if id == "cup" else COLA_H
	var phase := int(d.get("phase", 0))
	var target := Vector2(me.x, me.z)
	if phase >= 1:
		var l := _at(room, float(d.get("lx", 0.0)), float(d.get("ly", 0.0)))
		target = l
	var fall := sqrt(2.0 * h / 9.8)
	if id == "cup" and phase == 0:
		var w: Dictionary = d.get("wall", {})
		if not w.is_empty():
			var wp := _at(room, float(w["x"]) * AnomalyModule.SC, float(w["y"]) * AnomalyModule.SC)
			obj.position = Vector3(wp.x, me.y + h, wp.y)
			obj.rotation.z = sin(t * 18.0) * 0.5 * clampf(t / maxf(float(d.get("wob", 1.0)), 0.1), 0.0, 1.0)
		return
	if phase == 0:
		obj.position = Vector3(me.x, me.y + h, me.z)
		obj.rotation = Vector3(t * 3.0, 0.0, 0.0)
		return
	var since := t - float(d.get("tf", t))
	if phase == 1:
		var k := clampf(since / fall, 0.0, 1.0)
		var start := obj.position
		if id == "cup" and d.has("wall") and not (d["wall"] as Dictionary).is_empty():
			var w2: Dictionary = d["wall"]
			var wp2 := _at(room, float(w2["x"]) * AnomalyModule.SC, float(w2["y"]) * AnomalyModule.SC)
			start = Vector3(wp2.x, me.y + h, wp2.y)
		else:
			start = Vector3(target.x, me.y + h, target.y)
		obj.position = Vector3(lerpf(start.x, target.x, k), me.y + h * (1.0 - k * k), lerpf(start.z, target.y, k))
		obj.rotation = Vector3(since * 9.0, 0.0, since * 5.0)
	else:
		obj.position = Vector3(target.x, me.y + 0.04, target.y)
		obj.rotation = Vector3(0.0, 0.0, PI * 0.5)
