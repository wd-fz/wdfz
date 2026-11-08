class_name HandsView
extends Node3D
## The first-person hands and what they hold (hands.js, reference wd-fz.github.io@0bf508a), hung on the
## camera: the umbrella in the left hand, the torch in the right, the phone in whichever hand is free (both
## busy: it goes back in the pocket). The models are the old build's own geometry (tools/export_scenes
## --only hands); the places are its HAND_PLACE. Drawn over the world (no depth test) so a wall never
## cuts the hand, as the old separate hand scene did. They sway a little with the steps.

const PLACE := {"torch": {"p": [0.17, -0.24, -0.40], "r": [0.40, -0.05, 0.35]}, "brolly": {"p": [0.21, -0.27, -0.40], "r": [1.22, -0.05, 0.1]},
	"phone": {"p": [0.09, -0.16, -0.32], "r": [1.2, 0.0, 2.8]}}

var _hands := {}              # "L" / "R" → Node3D (current)
var _holding := {"L": "", "R": ""}
var _cache := {}
var _phase := 0.0
var _fill: OmniLight3D        # the hand scene's own near light (hands.js HANDS.near)
var _lens: Array[StandardMaterial3D] = []   # the torch's lens and bulb, to light and darken with the torch


## What is held now, from the state: torch lit, umbrella up, phone open.
static func uses(torch_on: bool, brolly_up: bool, phone_open: bool, shown: bool) -> Dictionary:
	var left := ""
	var right := ""
	if shown:
		if brolly_up:
			left = "brolly"
		if torch_on:
			right = "torch"
		if phone_open:
			if left == "":
				left = "phone"
			elif right == "":
				right = "phone"
	return {"L": left, "R": right}


func _make(item: String, side: String) -> Node3D:
	var key := item + "_" + side
	var path := "res://assets/campus/hands/%s.glb" % key
	var root := Node3D.new()
	root.name = "Hand_" + key
	if not ResourceLoader.exists(path):
		return root
	if not _cache.has(key):
		_cache[key] = load(path)
	var inst := (_cache[key] as PackedScene).instantiate() as Node3D
	if item == "torch":
		_lens.clear()
	root.add_child(inst)
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.layers = CampusLighting.HAND_LAYER    # only the ambient and this hand's own fill light touch it
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			if src is BaseMaterial3D:
				var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				mat.no_depth_test = true
				mat.render_priority = 20
				mat.disable_fog = true
				m.set_surface_override_material(s, mat)
				if item == "torch" and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not mat.vertex_color_use_as_albedo:
					_lens.append(mat)     # the lens (m3, 0xfff2c8) and the bulb (m4, white) are the unshaded ones
	return root


func _set_place(h: Node3D, item: String, sign: float) -> void:
	var pl: Dictionary = PLACE[item]
	var p: Array = pl["p"]
	var r: Array = pl["r"]
	h.position = Vector3(sign * float(p[0]), float(p[1]), float(p[2]))
	h.basis = Basis.from_euler(Vector3(float(r[0]), sign * float(r[1]), sign * float(r[2])), EULER_ORDER_XYZ)
	h.set_meta("base", h.position)


## The hand light: 0.35 of the camera fill plus 0.45 more with the torch on (hands.js handsTick), same colour as the fill.
static func fill_energy(cam_energy: float, torch_on: bool) -> float:
	return cam_energy * 0.35 + (0.45 * CampusLighting.ENERGY_POINT * 9.0 if torch_on else 0.0)


func _ensure_fill() -> void:
	if _fill != null and is_instance_valid(_fill):
		return
	_fill = OmniLight3D.new()
	_fill.name = "HandFill"
	_fill.light_cull_mask = CampusLighting.HAND_LAYER
	_fill.omni_range = 3.0
	_fill.omni_attenuation = 1.5
	_fill.position = Vector3(0.1, 0.25, 0.1)
	_fill.shadow_enabled = false
	add_child(_fill)


## Light the hands from the world's camera fill: its colour, a share of its energy, plus the torch's.
func light(cam_energy: float, cam_color: Color, torch_on: bool) -> void:
	_ensure_fill()
	_fill.light_color = cam_color
	_fill.light_energy = fill_energy(cam_energy, torch_on)
	_fill.visible = _holding["L"] != "" or _holding["R"] != ""
	# The lens shines and the bulb is white while it is lit; dark grey when the torch is off.
	for i in _lens.size():
		if is_instance_valid(_lens[i]):
			_lens[i].albedo_color = (Color("#fff2c8") if i == 0 else Color.WHITE) if torch_on else (Color("#30343a") if i == 0 else Color("#3a3e44"))


func update(delta: float, torch_on: bool, brolly_up: bool, phone_open: bool, shown: bool, moving: bool, running: bool) -> void:
	var u := uses(torch_on, brolly_up, phone_open, shown)
	for side: String in ["L", "R"]:
		var item := String(u[side])
		if item != String(_holding[side]):
			if _hands.has(side) and is_instance_valid(_hands[side]):
				(_hands[side] as Node3D).queue_free()
				_hands.erase(side)
			_holding[side] = item
			if item != "":
				var h := _make(item, side)
				add_child(h)
				_set_place(h, item, -1.0 if side == "L" else 1.0)
				_hands[side] = h
	_phase += delta * (9.0 if running else 6.0 if moving else 1.2)
	var amp := 0.018 if running else (0.009 if moving else 0.002)
	var i := 0
	for side: String in ["L", "R"]:
		if _hands.has(side) and is_instance_valid(_hands[side]):
			var h2 := _hands[side] as Node3D
			var b: Vector3 = h2.get_meta("base")
			var q := _phase + float(i)
			h2.position = b + Vector3(sin(q) * amp, absf(cos(q)) * amp, 0.0)
		i += 1


func held(side: String) -> String:
	return String(_holding.get(side, ""))
