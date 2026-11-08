class_name AnomalyFx
extends Node3D
## Placeholder scene presentation for the anomalies that have a place in the world (the Web
## version's fx/anomaly-fx.js is not ported): plain unlit primitives, no sounds. It only reads the
## anomaly module's state; nothing here writes back to the rules.
## Covered: rain streaks, moth swarm, exercising crowd, hand under the stall, board text, the struck-off
## roster, ceiling drips, the ritual circle, the second you, the falling cup and cola.
## Also: the hand on the shoulder (turn), the back-row classmate (repeat), the staring faces (stare),
## the feast table, the walker beyond the east fence (necker), the late shadow, the following lamp,
## the cold room's frost. Sound or text only: broad, bell13, bells, loop, shifting.

const CUP_H := AnomalyModule.CUP_H
const COLA_H := AnomalyModule.COLA_H

var _props: Node3D
var _key := ""
var _extra: Dictionary = {}


## `an`: the module's state; `room`: the current room layout (null outside); `feet`: the player's
## position in scene metres (x, floor height, z); `yaw_dir`: the player's facing as a scene xz vector.
func update(dt: float, an: Dictionary, room: Variant, scene: String, feet: Vector3, facing: Vector2) -> void:
	var id := String(an.get("id", "")) if an.get("active", false) else ""
	var data: Dictionary = an.get("data", {})
	if id != "" and data.has("scene") and String(data["scene"]) != scene:
		id = ""
	var key := id
	if key != _key:
		_clear()
		_key = key
		if key != "":
			_props = Node3D.new()
			_props.name = "Anomaly_" + key
			add_child(_props)
			_build(key, data, room, feet, facing)
	if _props != null:
		_animate(id, float(an.get("t", 0.0)), data, room, feet, facing, dt)


func current() -> String:
	return _key


func shown_count() -> int:
	return _props.get_child_count() if is_instance_valid(_props) else 0


func _clear() -> void:
	if is_instance_valid(_props):
		_props.queue_free()
	_props = null
	_extra = {}


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


func _label(text: String, size: float, color: Color, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = 64
	l.modulate = color
	l.shaded = false
	l.double_sided = true
	l.no_depth_test = false
	l.position = pos
	_props.add_child(l)
	return l


func _at(room: Variant, x: float, y: float) -> Vector2:
	return CampusGeometry.to_scene(room, Vector2(x, y))


func _figure(color: Color, height: float = 1.7) -> Node3D:
	var n := Node3D.new()
	n.add_child(FigureModel.make("person", color, true, height / 1.85))
	_props.add_child(n)
	return n


func _particles(count: int, lifetime: float, size: Vector3, color: Color, extents: Vector3, gravity: Vector3, vel: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = count
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.gravity = gravity
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.local_coords = false
	var box := BoxMesh.new()
	box.size = size
	p.mesh = box
	p.material_override = _unlit(color)
	_props.add_child(p)
	return p


func _build(id: String, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2) -> void:
	match id:
		"rain", "raindots":
			var rain := WeatherFx.new()
			_props.add_child(rain)
			rain.setup_rain(feet)
			_extra["rain"] = rain
		"moth":
			var msrc: Dictionary = d.get("src", {"x": 0.0, "y": 0.0})
			var ms := _at(room, float(msrc["x"]), float(msrc["y"]))
			var swarm := WeatherFx.new()
			_props.add_child(swarm)
			swarm.setup_moths(Vector3(ms.x, feet.y, ms.y))
			_extra["swarm"] = swarm
		"exercise":
			var src: Dictionary = d.get("src", {"x": 0.0, "y": 0.0})
			var c := _at(room, float(src["x"]), float(src["y"]))
			_extra["c"] = Vector3(c.x, feet.y, c.y)
			var figs: Array[Node3D] = []
			for i in 14:
				var f := _figure(Color(0.86, 0.86, 0.9))
				var a := TAU * i / 14.0
				f.position = Vector3(c.x + cos(a) * 3.0, feet.y, c.y + sin(a) * 3.0)
				figs.append(f)
			_extra["figs"] = figs
		"hand":
			var hand := _mesh(BoxMesh.new(), _unlit(Color(0.82, 0.75, 0.7)))
			(hand.mesh as BoxMesh).size = Vector3(0.09, 0.03, 0.26)
			_extra["hand"] = hand
		"chalk":
			var board := _label("下一次", 0.006, Color(0.95, 0.95, 0.9), Vector3.ZERO)
			if d.has("until"):
				board.text = "下一次\n%s" % SchoolClock.fmt_clock(float(d["until"]))
			_extra["board"] = board
		"roster":
			var paper := _mesh(BoxMesh.new(), _unlit(Color(0.92, 0.9, 0.82)))
			(paper.mesh as BoxMesh).size = Vector3(0.55, 0.75, 0.01)
			var p := _at(room, float(d.get("rx", 0.0)), float(d.get("ry", 0.0)))
			paper.position = Vector3(p.x, feet.y + 1.35, p.y)
			var mark := _label("名单\n———\n~~我~~", 0.004, Color(0.75, 0.1, 0.1), Vector3(p.x, feet.y + 1.35, p.y))
			mark.position += Vector3(0, 0, 0.012)
			_extra["paper"] = paper
			_extra["mark"] = mark
		"leak":
			for pt: Dictionary in d.get("pts", []):
				var p := _at(room, float(pt["x"]), float(pt["y"]))
				var drip := _particles(10, 0.9, Vector3(0.02, 0.06, 0.02), Color(0.5, 0.65, 0.8, 0.85), Vector3(0.05, 0.02, 0.05), Vector3(0, -9, 0), 0.2)
				drip.position = Vector3(p.x, feet.y + 2.6, p.y)
				var pool := CylinderMesh.new()
				pool.top_radius = 0.28
				pool.bottom_radius = 0.28
				pool.height = 0.01
				var pm := _mesh(pool, _unlit(Color(0.2, 0.28, 0.36), 0.8))
				pm.position = Vector3(p.x, feet.y + 0.01, p.y)
		"rite":
			var cc := _at(room, float((d.get("c", {"x": 0.0}) as Dictionary)["x"]), float((d.get("c", {"y": 0.0}) as Dictionary)["y"]))
			var ring := TorusMesh.new()
			ring.inner_radius = 1.5
			ring.outer_radius = 1.58
			_mesh(ring, _unlit(Color(0.9, 0.9, 0.85)), Vector3(cc.x, feet.y + 0.015, cc.y))
			for i in 4:
				var a := PI * 0.25 + PI * 0.5 * i
				var cm := CylinderMesh.new()
				cm.top_radius = 0.03
				cm.bottom_radius = 0.035
				cm.height = 0.3
				var cp := Vector3(cc.x + cos(a) * 1.54, feet.y + 0.15, cc.y + sin(a) * 1.54)
				_mesh(cm, _unlit(Color(0.95, 0.94, 0.88)), cp)
				var flame := SphereMesh.new()
				flame.radius = 0.03
				flame.height = 0.07
				_mesh(flame, _unlit(Color(1.0, 0.75, 0.3)), cp + Vector3(0, 0.19, 0))
				var lamp := OmniLight3D.new()
				lamp.light_color = Color(1.0, 0.7, 0.35)
				lamp.light_energy = 0.7
				lamp.omni_range = 3.0
				lamp.position = cp + Vector3(0, 0.25, 0)
				_props.add_child(lamp)
		"twin":
			_extra["twin"] = _figure(Color(0.03, 0.03, 0.04))
		"turn", "repeat":
			var f := _figure(Color(0.04, 0.04, 0.05), 1.75 if id == "turn" else 1.25)
			if id == "turn" and bool(d.get("smile", false)):
				var face := SphereMesh.new()
				face.radius = 0.13
				face.height = 0.26
				var fm := MeshInstance3D.new()
				fm.mesh = face
				fm.material_override = _unlit(Color(0.9, 0.88, 0.82))
				fm.position = Vector3(0, 1.62, 0.12)
				f.add_child(fm)
			_extra["fig"] = f
		"stare":
			var faces: Array[Node3D] = []
			for i in 12:
				var head := SphereMesh.new()
				head.radius = 0.12
				head.height = 0.24
				var hm := _mesh(head, _unlit(Color(0.86, 0.84, 0.8)))
				faces.append(hm)
			_extra["faces"] = faces
		"feast":
			var table := _mesh(BoxMesh.new(), _unlit(Color(0.42, 0.3, 0.2)))
			(table.mesh as BoxMesh).size = Vector3(1.0, 0.75, 6.0)
			_extra["table"] = table
			var plates: Array[Node3D] = []
			for i in 8:
				var plate := CylinderMesh.new()
				plate.top_radius = 0.13
				plate.bottom_radius = 0.1
				plate.height = 0.03
				plates.append(_mesh(plate, _unlit(Color(0.95, 0.95, 0.92))))
			_extra["plates"] = plates
			var steam := _particles(30, 1.5, Vector3(0.03, 0.08, 0.03), Color(0.9, 0.9, 0.9, 0.35), Vector3(0.4, 0.05, 2.8), Vector3(0, 0.5, 0), 0.1)
			_extra["steam"] = steam
		"necker":
			var walker := Node3D.new()
			_props.add_child(walker)
			walker.add_child(FigureModel.make("neck", Color(0.05, 0.05, 0.06), true))
			_extra["walker"] = walker
		"shadow":
			var disc := CylinderMesh.new()
			disc.top_radius = 0.42
			disc.bottom_radius = 0.42
			disc.height = 0.01
			var sm := _mesh(disc, _unlit(Color(0.0, 0.0, 0.0), 0.75))
			sm.scale = Vector3(1.0, 1.0, 2.2)
			_extra["shadow"] = sm
			_extra["trail"] = []
		"lamps":
			var lamp := OmniLight3D.new()
			lamp.light_color = Color(1.0, 0.95, 0.8)
			lamp.light_energy = 1.4
			lamp.omni_range = 6.0
			_props.add_child(lamp)
			_extra["lamp"] = lamp
		"cold":
			var frost := _particles(120, 2.0, Vector3(0.02, 0.02, 0.02), Color(0.9, 0.95, 1.0, 0.8), Vector3(2.5, 1.2, 2.5), Vector3(0, -0.2, 0), 0.1)
			_extra["frost"] = frost
		"cup":
			var cup := CylinderMesh.new()
			cup.top_radius = 0.11
			cup.bottom_radius = 0.085
			cup.height = 0.3
			_extra["obj"] = _mesh(cup, _unlit(Color(0.95, 0.95, 0.97)))
			var lid := _mesh(CylinderMesh.new(), _unlit(Color(0.7, 0.6, 0.85)), Vector3(0, 0.16, 0))
			(lid.mesh as CylinderMesh).top_radius = 0.115
			(lid.mesh as CylinderMesh).bottom_radius = 0.115
			(lid.mesh as CylinderMesh).height = 0.04
			lid.get_parent().remove_child(lid)
			(_extra["obj"] as Node3D).add_child(lid)
		"cola":
			var can := CylinderMesh.new()
			can.top_radius = 0.09
			can.bottom_radius = 0.09
			can.height = 0.3
			_extra["obj"] = _mesh(can, _unlit(Color(0.85, 0.1, 0.1)))


func _animate(id: String, t: float, d: Dictionary, room: Variant, feet: Vector3, facing: Vector2, dt: float) -> void:
	var me := Vector3(feet.x, feet.y, feet.z)
	match id:
		"rain", "raindots":
			(_extra["rain"] as WeatherFx).update_rain(dt, Vector3(me.x, me.y + 1.7, me.z), me.y)
		"moth":
			(_extra["swarm"] as WeatherFx).update_moths(dt, Vector3(me.x, me.y + 1.7, me.z), t, bool(d.get("hard", false)))
		"exercise":
			var swing := sin(t * 5.0) * 0.12
			for f: Node3D in _extra["figs"]:
				f.rotation.z = swing
				f.position.y = me.y + absf(swing) * 0.4
		"hand":
			var hand := _extra["hand"] as MeshInstance3D
			var reach := clampf(t / 1.2, 0.0, 1.0)
			var f2 := facing.normalized() if facing.length() > 0.01 else Vector2(0, -1)
			var dist := 1.6 - 0.35 * reach
			hand.position = Vector3(me.x + f2.x * dist, me.y + 0.03, me.z + f2.y * dist)
			hand.rotation.y = atan2(f2.x, f2.y)
		"chalk":
			var board := _extra["board"] as Label3D
			var f3 := facing.normalized() if facing.length() > 0.01 else Vector2(0, -1)
			board.position = Vector3(me.x + f3.x * 2.0, me.y + 1.45, me.z + f3.y * 2.0)
			board.rotation.y = atan2(-f3.x, -f3.y)
			board.modulate.a = clampf(t / 1.5, 0.0, 1.0)
		"roster":
			var gone := bool(d.get("done", false))
			(_extra["paper"] as Node3D).visible = not gone
			(_extra["mark"] as Node3D).visible = not gone
		"twin":
			var tw := _extra["twin"] as Node3D
			var p := _at(room, float(d.get("x", 0.0)), float(d.get("y", 0.0)))
			tw.position = Vector3(p.x, me.y, p.y)
			tw.rotation.y = atan2(me.x - p.x, me.z - p.y)
		"cup", "cola":
			_animate_fall(id, t, d, room, me)
		"turn", "repeat":
			var f4 := facing.normalized() if facing.length() > 0.01 else Vector2(0, -1)
			var back := 0.9 if id == "turn" else 0.85
			var fig := _extra["fig"] as Node3D
			fig.position = Vector3(me.x - f4.x * back, me.y, me.z - f4.y * back)
			fig.rotation.y = atan2(f4.x, f4.y)
		"stare":
			var f5 := facing.normalized() if facing.length() > 0.01 else Vector2(0, -1)
			var side := Vector2(-f5.y, f5.x)
			var faces: Array = _extra["faces"]
			for i in faces.size():
				var row := float(i / 4)
				var col := float(i % 4) - 1.5
				var p := Vector2(me.x, me.z) + f5 * (2.2 + row * 1.2) + side * col * 1.1
				(faces[i] as Node3D).position = Vector3(p.x, me.y + 1.15, p.y)
		"feast":
			var f6 := facing.normalized() if facing.length() > 0.01 else Vector2(0, -1)
			var c := Vector2(me.x, me.z) + f6 * 2.4
			if not _extra.has("at"):
				_extra["at"] = c
				_extra["dir"] = f6
			var at: Vector2 = _extra["at"]
			var dir: Vector2 = _extra["dir"]
			var table := _extra["table"] as Node3D
			table.position = Vector3(at.x, me.y + 0.375, at.y)
			table.rotation.y = atan2(dir.x, dir.y) + PI * 0.5
			var across := Vector2(-dir.y, dir.x)
			var plates: Array = _extra["plates"]
			for i in plates.size():
				var off := (float(i % 4) - 1.5) * 1.3
				var sidek := 0.3 if i < 4 else -0.3
				var pp := at + across * off + dir * sidek
				(plates[i] as Node3D).position = Vector3(pp.x, me.y + 0.77, pp.y)
			(_extra["steam"] as Node3D).global_position = Vector3(at.x, me.y + 0.8, at.y)
			(_extra["steam"] as Node3D).rotation.y = table.rotation.y
		"necker":
			var wall_x := float(CampusData.campus().get("bound_map", {}).get("x1", 830)) * 2.0 + 30.0
			var p2 := _at(room, wall_x, me.z / CampusGeometry.U2M if room == null else 0.0)
			(_extra["walker"] as Node3D).position = Vector3(p2.x, 0.0, me.z)
		"shadow":
			var trail: Array = _extra["trail"]
			trail.append(Vector3(me.x, me.y, me.z))
			var lag := 30
			while trail.size() > lag:
				trail.pop_front()
			var tail: Vector3 = trail[0]
			(_extra["shadow"] as Node3D).position = Vector3(tail.x, me.y + 0.012, tail.z)
		"lamps":
			var lamp := _extra["lamp"] as OmniLight3D
			var target := Vector3(me.x, me.y + 2.6, me.z)
			lamp.position = target if lamp.position == Vector3.ZERO else lamp.position.lerp(target, clampf(dt * 2.0, 0.0, 1.0))
		"cold":
			(_extra["frost"] as Node3D).global_position = Vector3(me.x, me.y + 1.2, me.z)


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
