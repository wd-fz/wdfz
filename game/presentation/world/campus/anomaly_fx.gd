class_name AnomalyFx
extends Node3D
## Adapter for read-only anomaly visuals. Weather and world props own their animations;
## the module alone owns danger, damage, choices and scene lifetime.
var ground_height: Callable
var _props: Node3D
var _key := ""
var _quality := -1
var particle_quality := -1
var _particle_quality := -1
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
	if id!=_key or _quality!=CampusData.tier or _particle_quality!=particle_quality or t<_last_t:
		_clear()
		_key=id
		_quality=CampusData.tier
		_particle_quality=particle_quality
		if id!="":
			_props=Node3D.new()
			_props.name="Anomaly_"+id
			add_child(_props)
			_build(id,data,room,feet,facing,t)
	_last_t=t
	if _props==null: return
	var camera_pos:=eye if eye.is_finite() else feet+Vector3(0,CameraMotion.EYE,0)
	if _extra.has("original"):
		(_extra["original"] as AnomalyProps).advance(dt,data,room,feet,float(an.get("acc",0)))
	if _extra.has("rain"): (_extra["rain"] as WeatherFx).update_rain(dt,camera_pos,feet.y)
	if _extra.has("swarm"): (_extra["swarm"] as WeatherFx).update_moths(dt,camera_pos,float(an.get("acc",0)),hard)
	if _extra.has("falling"): (_extra["falling"] as FallingProps).advance(dt,t,data,room,feet)


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


func _at(room: Variant, x: float, y: float) -> Vector2:
	return CampusGeometry.to_scene(room, Vector2(x, y))


func _build(id: String, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2, t: float) -> void:
	if id in AnomalyProps.KINDS:
		var props:=AnomalyProps.new()
		props.seed_value=visual_seed if visual_seed>=0 else _visual_random.randi()
		_props.add_child(props)
		props.build(id,d,room,feet,facing,CampusData.tier if particle_quality<0 else particle_quality)
		_extra["original"]=props
		return
	match id:
		"rain":
			var rain:=WeatherFx.new()
			_props.add_child(rain)
			rain.setup_rain(feet,particle_quality)
			_extra["rain"]=rain
		"moth":
			var src: Dictionary=d.get("src",{"x":0.0,"y":0.0})
			var p:=_at(room,src["x"],src["y"])
			var swarm:=WeatherFx.new()
			_props.add_child(swarm)
			swarm.setup_moths(Vector3(p.x,feet.y,p.y),particle_quality)
			_extra["swarm"]=swarm
		"cup","cola":
			var falling:=FallingProps.new()
			falling.ground_height=ground_height
			_props.add_child(falling)
			falling.build(id,d,room,feet,t,CampusData.tier,visual_seed if visual_seed>=0 else _visual_random.randi())
			_extra["falling"]=falling
