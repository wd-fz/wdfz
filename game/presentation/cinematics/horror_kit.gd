class_name HorrorKit
extends RefCounted
## Shared horror pieces for death cinematics and world scares. Presentation only: no gameplay
## state and no random draws. Hands and heads are procedural, smooth-shaded meshes with jointed
## rigs; skin is one spatial shader that avoids renderer-specific features (no SSS, no screen
## reads), so it runs on Forward+, Mobile and Compatibility alike.
## Conventions: a hand points along -Z, back of the hand +Y, palm -Y, wrist at the origin and the
## forearm along +Z; a head faces -Z with its origin at the middle of the skull. Sizes are a real
## adult's, in metres; callers scale the returned node. Meshes and materials are cached, and their
## segment counts follow the 0..4 graphics tier (CampusData.tier unless "quality" is given).

const FINGER_X := [.029,.0095,-.0095,-.027]      # index..little, times side (thumb side = +X when side = 1)
const FINGER_Z := [-.085,-.09,-.087,-.078]
const FINGER_LEN := [[.043,.025,.02],[.047,.029,.021],[.044,.027,.021],[.034,.02,.018]]
const FINGER_R := [.0086,.009,.0085,.0075]
const FINGER_YAW := [-.06,0.0,.06,.15]
const FINGER_SPREAD := [-.17,-.045,.09,.23]
const THUMB_LEN := [.04,.032,.027]
const JAW_PIVOT := Vector3(0,-.026,.006)
const LIP_Y := -.43                             # the mouth line, as the y of a unit direction
const TONES := {
	"wax":{"base_color":Color(.66,.65,.59),"vein_color":Color(.36,.44,.48),"deep_color":Color(.035,.03,.03),"vein_amount":.32,"mottle":.22,
		"rim_color":Color(.55,.66,.73),"rim_strength":.55,"rim_emit":.05,"gloss":.2,"shininess":20.0},
	"shadow":{"base_color":Color(.022,.025,.028),"vein_color":Color(.05,.06,.07),"deep_color":Color(0,0,0),"vein_amount":.3,"mottle":.4,
		"rim_color":Color(.42,.52,.6),"rim_strength":1.3,"rim_emit":.3,"gloss":.12,"shininess":12.0},
	"nail":{"base_color":Color(.6,.58,.5),"vein_color":Color(.42,.4,.35),"deep_color":Color(.02,.016,.012),"vein_amount":.1,"mottle":.5,
		"rim_color":Color(.5,.55,.55),"rim_strength":.3,"rim_emit":.02,"gloss":.7,"shininess":60.0,"noise_scale":140.0},
	"eye":{"base_color":Color(.5,.53,.5),"vein_color":Color(.4,.44,.44),"deep_color":Color(.03,.03,.03),"vein_amount":.15,"mottle":.4,
		"rim_color":Color(.5,.58,.6),"rim_strength":.1,"rim_emit":.0,"gloss":.35,"shininess":40.0},
	"cavity":{"base_color":Color(.008,.006,.006),"vein_color":Color(.008,.006,.006),"deep_color":Color(0,0,0),"vein_amount":0.0,"mottle":0.0,
		"rim_color":Color(0,0,0),"rim_strength":0.0,"rim_emit":0.0,"gloss":0.0,"shininess":8.0},
}
const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec3 base_color : source_color = vec3(.78,.77,.71);
uniform vec3 vein_color : source_color = vec3(.33,.41,.46);
uniform vec3 deep_color : source_color = vec3(.04,.035,.035);
uniform float vein_amount = .6;
uniform float mottle = .5;
uniform float noise_scale = 55.0;
uniform float vertex_shade = 1.0;
uniform float wrap = .5;
uniform vec3 rim_color : source_color = vec3(.55,.66,.73);
uniform float rim_strength = .55;
uniform float rim_emit = .05;
uniform float rim_power = 3.0;
uniform float gloss = .2;
uniform float shininess = 20.0;
uniform float glow = 0.0;
uniform vec3 vein_stretch = vec3(1.0, 1.0, .3);
varying vec3 obj;
float hash(vec3 p) { p = fract(p * .3183099 + .1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { obj = VERTEX; }
void fragment() {
	vec3 p = obj * noise_scale * vein_stretch;
	float ridge = 1.0 - abs((noise(p) * .65 + noise(p * 2.03 + 7.1) * .35) * 2.0 - 1.0);
	float vein = smoothstep(.9, .985, ridge) * vein_amount;
	float blot = noise(p * .17 + 3.0) * .7 + noise(p * .6 + 11.0) * .3 - .5;
	// Baked shade is perceptual (like an sRGB value), so darken in linear light by its square-ish.
	float shade = pow(mix(1.0, COLOR.r, vertex_shade), 2.2);
	vec3 skin = mix(base_color, vein_color, clamp(vein + blot * mottle, 0.0, 1.0));
	ALBEDO = mix(deep_color, skin, shade);
	ROUGHNESS = .6;
	SPECULAR = .3;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * fres * rim_emit * shade + ALBEDO * glow;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * w / PI;
	vec3 h = normalize(LIGHT + VIEW);
	// Creases, sockets and the fading forearm (dark albedo) take no rim or gloss either.
	float lit = clamp(dot(ALBEDO, vec3(1.0)) / max(dot(base_color, vec3(1.0)), .001), 0.0, 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * lit * (pow(max(dot(NORMAL, h), 0.0), shininess) * gloss * max(ndl, 0.0) + rim_color * fres * rim_strength * clamp(ndl + .65, 0.0, 1.0)) / PI;
}
"""

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _skins: Dictionary = {}
static var _shader: Shader


static func tier(quality: Variant = -1) -> int:
	return clampi(CampusData.tier if int(quality) < 0 else int(quality), 0, 4)


static func clear_cache() -> void:
	_meshes.clear()
	_materials.clear()
	_skins.clear()


# ---- materials ----

## The skin material: a preset name ("wax", "shadow", "nail", "eye", "cavity") or a Color for a tinted
## silhouette (dark colours read as a "shadow" with the rim; light ones as tinted wax). glow adds a
## little self-light so a world prop stays readable in a dark room.
static func skin(tone: Variant = "wax", glow: float = 0.0, vertex_shade: bool = true) -> ShaderMaterial:
	var key := "%s|%.3f|%s" % [str(tone), glow, vertex_shade]
	if _materials.has(key): return _materials[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var params: Dictionary
	if tone is Color:
		var col: Color = tone
		params = (TONES["shadow"] if col.get_luminance() < .2 else TONES["wax"]).duplicate()
		params["base_color"] = col
		if col.get_luminance() < .2:
			params["vein_color"] = col.darkened(.35)
			params["vein_amount"] = .15
		else:
			params["vein_color"] = (params["vein_color"] as Color) * (col.get_luminance() / (TONES["wax"]["base_color"] as Color).get_luminance())
	else:
		params = TONES.get(String(tone), TONES["wax"])
	var m := ShaderMaterial.new()
	m.shader = _shader
	for name: String in params: m.set_shader_parameter(name, params[name])
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("vertex_shade", 1.0 if vertex_shade else 0.0)
	_materials[key] = m
	return m


static func is_dark(tone: Variant) -> bool:
	return (tone is Color and (tone as Color).get_luminance() < .2) or String(str(tone)) in ["shadow", "cavity"]


## The skin for an imported figure (its baked vertex shades are ignored): a dark tint gets the rim-lit shadow look.
static func figure_skin(col: Color) -> ShaderMaterial:
	return skin(col, 0.0, false)


## Put one material on every mesh under node (shadow casting off, like the other cinematic props).
static func dress(node: Node, mat: Material) -> void:
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---- the hand ----

## opts: long (finger length multiplier, 1.1: a little too long), extra (a fourth phalanx on each finger),
## thin (0..1, bony: thinner skin, bigger knuckles), arm (forearm length, m), side (1 right, -1 mirrored),
## tone (skin preset or Color), glow, nails (true), quality (tier).
static func hand(opts: Dictionary = {}) -> Node3D:
	var q := tier(opts.get("quality", -1))
	var long := float(opts.get("long", 1.15))
	var thin := clampf(float(opts.get("thin", 0.0)), 0.0, 1.0)
	var extra := bool(opts.get("extra", false))
	var side := -1.0 if float(opts.get("side", 1.0)) < 0 else 1.0
	var tone: Variant = opts.get("tone", "wax")
	var glow := float(opts.get("glow", 0.0))
	var mat := skin(tone, glow)
	var nail: Material = null
	if bool(opts.get("nails", true)): nail = mat if is_dark(tone) else skin("nail", glow)
	var flesh := 1.0 - .2 * thin
	var root := Node3D.new()
	root.name = "HorrorHand"
	_part(root, "Forearm", _forearm(float(opts.get("arm", .26)), flesh, side, q), mat)
	var wrist := Node3D.new()
	wrist.name = "Wrist"
	root.add_child(wrist)
	_part(wrist, "Palm", _palm(flesh, thin, side, q), mat)
	var fingers: Array = []
	for i in 4:
		var lens: Array = FINGER_LEN[i]
		var segs: Array = [lens[0] * long, lens[1] * long, lens[2] * (1.0 + (long - 1.0) * .6)]
		if extra: segs.insert(2, lens[1] * long * .8)
		var base := Node3D.new()
		base.name = "Finger%d" % i
		base.position = Vector3(FINGER_X[i] * side, .002, FINGER_Z[i])
		wrist.add_child(base)
		fingers.append(_chain(base, segs, FINGER_R[i] * .93 * flesh, thin, q, mat, nail))
	var thumb_base := Node3D.new()
	thumb_base.name = "Thumb"
	thumb_base.position = Vector3(.022 * side, -.009, -.012)
	thumb_base.rotation = Vector3(.22, -.5 * side, -.7 * side)
	wrist.add_child(thumb_base)
	var thumb := _chain(thumb_base, [THUMB_LEN[0], THUMB_LEN[1] * long, THUMB_LEN[2] * (1.0 + (long - 1.0) * .6)], .0128 * flesh, thin, q, mat, nail)
	root.set_meta("horror_hand", {"fingers": fingers, "thumb": thumb, "wrist": wrist, "side": side})
	pose_hand(root, .15, .2)
	return root


## Every finger joint (thumb first, then index..little; each a chain of Node3D joints, base to tip).
static func hand_joints(hand_node: Node3D) -> Array:
	var rig: Dictionary = hand_node.get_meta("horror_hand")
	var all: Array = [rig["thumb"]]
	all.append_array(rig["fingers"])
	return all


## Pose a hand from scratch (pure: the same arguments always give the same transforms, nothing accumulates).
## curl: 0 flat, 1 fist, negative bends the fingers back. spread: 0 together, 1 splayed.
## per_finger: optional, index 0 = thumb, 1..4 = index..little; each entry null (use curl), a float
## (that finger's curl) or an Array of joint angles in radians, base to tip (a claw, a hook...).
## wrist: x bends the hand towards the palm (+) or back (-), y turns it sideways.
static func pose_hand(hand_node: Node3D, curl: float, spread: float, per_finger: Array = [], wrist: Vector2 = Vector2.ZERO) -> void:
	var rig: Dictionary = hand_node.get_meta("horror_hand")
	var side: float = rig["side"]
	(rig["wrist"] as Node3D).rotation = Vector3(-wrist.x, wrist.y * side, 0)
	var chains: Array = hand_joints(hand_node)
	for f in chains.size():
		var chain: Array = chains[f]
		var entry: Variant = per_finger[f] if f < per_finger.size() else null
		var c: float = float(entry) if (entry is float or entry is int) else curl
		var angles: Array
		if f == 0: angles = [c * .35, c * .7, c * .9]
		else: angles = [c * 1.35, c * 1.6, c * 1.05]
		var yaw := 0.0 if f == 0 else (float(FINGER_YAW[f - 1]) + spread * float(FINGER_SPREAD[f - 1])) * side
		if f == 0: yaw = -spread * .35 * side
		for j in chain.size():
			var a: float = float(angles[0 if j == 0 else (2 if j == chain.size() - 1 else 1)])
			if entry is Array and j < (entry as Array).size(): a = float(entry[j])
			(chain[j] as Node3D).rotation = Vector3(-a, yaw if j == 0 else 0.0, 0)


static func _part(parent: Node3D, name: String, shape: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = shape
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _chain(base: Node3D, lengths: Array, r: float, thin: float, q: int, mat: Material, nail: Material) -> Array:
	var joints: Array = []
	var parent := base
	var n := lengths.size()
	for j in n:
		var joint := Node3D.new()
		joint.name = "J%d" % j
		if j > 0: joint.position = Vector3(0, 0, -float(lengths[j - 1]))
		parent.add_child(joint)
		var tip := j == n - 1
		var r0 := r * (1.0 - .22 * float(j) / maxf(1, n - 1))
		var r1 := r0 * (.7 if tip else .9)
		var knuckle := 0.0 if tip else r * (.07 + .16 * thin)
		_part(joint, "Bone", _phalanx(float(lengths[j]), r0, r1, knuckle, tip, q), mat)
		if tip and nail != null:
			_part(joint, "Nail", _nail(float(lengths[j]), r0, r1, q), nail)
		joints.append(joint)
		parent = joint
	return joints


## A swept surface: rows+1 rings from f(u, v) -> [Vector3, shade]. A ring collapsed to one point
## becomes a pole; closed = false makes an open grid (v in [0,1] inclusive). Normals are smooth.
## bones: optional f2(u, v) -> [bone a, bone b, weight of b] for a two-bone skin.
static func _sweep(rows: int, seg: int, f: Callable, closed: bool = true, bones: Callable = Callable()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := seg if closed else seg + 1
	var starts := PackedInt32Array()
	var poles: Array[bool] = []
	var n := 0
	for i in rows + 1:
		var u := float(i) / rows
		var ring: Array = []
		for j in cols: ring.append(f.call(u, float(j) / seg))
		var pole := closed
		if closed:
			for v: Array in ring:
				if (v[0] as Vector3).distance_squared_to(ring[0][0]) > 1e-14:
					pole = false
					break
		starts.append(n)
		poles.append(pole)
		for j in (1 if pole else cols):
			var v: Array = ring[j]
			st.set_color(Color(v[1], v[1], v[1]))
			if bones.is_valid():
				var b: Array = bones.call(u, float(j) / seg)
				st.set_bones(PackedInt32Array([b[0], b[1], 0, 0]))
				st.set_weights(PackedFloat32Array([1.0 - float(b[2]), b[2], 0, 0]))
			st.add_vertex(v[0])
			n += 1
	for i in rows:
		var a := starts[i]
		var b := starts[i + 1]
		if poles[i] and poles[i + 1]: continue
		for j in seg:
			var k := (j + 1) % cols
			if poles[i]: _tri(st, a, b + k, b + j)
			elif poles[i + 1]: _tri(st, a + j, a + k, b)
			else:
				_tri(st, a + j, a + k, b + k)
				_tri(st, a + j, b + k, b + j)
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: int, b: int, c: int) -> void:
	st.add_index(a)
	st.add_index(b)
	st.add_index(c)


static func _phalanx_r(s: float, length: float, r0: float, r1: float, knuckle: float) -> float:
	var t := clampf(s / length, 0.0, 1.0)
	return lerpf(r0, r1, t) * (1.0 - .025 * sin(t * PI)) + knuckle * exp(-pow((t - 1.0) / .22, 2.0))


## One phalanx along -Z from its joint: rounded ends overlap the neighbours, a knuckle swell at the far
## joint, creases darker on the palm side; the last one tapers to a darkened fingertip.
static func _phalanx(length: float, r0: float, r1: float, knuckle: float, tip: bool, q: int) -> Mesh:
	var key := "ph|%.5f|%.5f|%.5f|%.5f|%s|%d" % [length, r0, r1, knuckle, tip, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [6, 8, 10, 12, 14][q]
	var body: int = [3, 4, 5, 6, 7][q]
	var cap: int = [2, 2, 3, 3, 4][q]
	var rows := body + cap * 2
	var re := _phalanx_r(length, length, r0, r1, knuckle)
	var ce := re * (1.45 if tip else 1.0)
	var f := func(u: float, v: float) -> Array:
		var i := u * rows
		var s: float
		var r: float
		if i <= cap:
			var a := i / cap * PI * .5
			s = -r0 * cos(a)
			r = r0 * sin(a)
		elif i >= rows - cap:
			var a := (rows - i) / cap * PI * .5
			s = length + ce * cos(a)
			r = re * sin(a)
		else:
			s = (i - cap) / body * length
			r = _phalanx_r(s, length, r0, r1, knuckle)
		var th := v * TAU
		var up := sin(th)
		var shade := 1.0 - .3 * maxf(0.0, -up) * (exp(-pow(s / (r0 * 1.2), 2.0)) + exp(-pow((s - length) / (r0 * 1.2), 2.0)))
		if tip:
			var tt := clampf((s - length * .4) / (length * .6 + ce), 0.0, 1.0)
			shade *= lerpf(1.0, .4, tt * tt)
			if up > .2 and s > length * .38: shade *= .72
		return [Vector3(r * cos(th), r * up * .86, -s), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]


## The nail: a curved plate over the top of the last phalanx; its free edge and folds are dark.
static func _nail(length: float, r0: float, r1: float, q: int) -> Mesh:
	var key := "nail|%.5f|%.5f|%.5f|%d" % [length, r0, r1, q]
	if _meshes.has(key): return _meshes[key]
	var re := _phalanx_r(length, length, r0, r1, 0.0)
	var ce := re * 1.45
	var rows: int = [2, 3, 3, 4, 5][q]
	var cols: int = [3, 4, 5, 6, 6][q]
	var f := func(u: float, v: float) -> Array:
		var s := lerpf(length * .42, length + ce * .62, u)
		var r: float
		if s <= length: r = _phalanx_r(s, length, r0, r1, 0.0)
		else: r = re * sin(acos(clampf((s - length) / ce, 0.0, 1.0)))
		var th := PI * .5 + (v - .5) * 1.9
		var edge := absf(v - .5) * 2.0
		var shade := .9 - .55 * smoothstep(.6, 1.0, edge) - .45 * smoothstep(.15, 0.0, u)
		shade = lerpf(shade, .06, smoothstep(.72, 1.0, u))
		r += .0006
		return [Vector3(r * cos(th) * .96, r * sin(th) * .86 + .0003, -s), shade]
	_meshes[key] = _sweep(rows, cols, f, false)
	return _meshes[key]


static func _palm(flesh: float, thin: float, side: float, q: int) -> Mesh:
	var key := "palm|%.3f|%.3f|%d|%d" % [flesh, thin, side, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [10, 14, 18, 22, 26][q]
	var body: int = [4, 5, 7, 9, 10][q]
	var cap: int = [2, 2, 3, 3, 4][q]
	var rows := body + cap * 2
	var length := .084
	var f := func(u: float, v: float) -> Array:
		var i := u * rows
		var t: float
		var z: float
		var k := 1.0
		if i <= cap:
			var a := i / cap * PI * .5
			t = 0.0
			z = .013 * cos(a)
			k = sin(a)
		elif i >= rows - cap:
			var a := (rows - i) / cap * PI * .5
			t = 1.0
			z = -length - .011 * cos(a)
			k = sin(a)
		else:
			t = (i - cap) / body
			z = -t * length
		var w := lerpf(.024, .041, smoothstep(0.0, .55, t)) * flesh * k
		var h := lerpf(.0165, .0125, t) * (1.0 - .12 * thin) * k
		var th := v * TAU
		var c := cos(th)
		var s := sin(th)
		var x := w * signf(c) * pow(absf(c), .62)
		var y := h * signf(s) * pow(absf(s), .62)
		if s > 0:
			var bumps := 0.0
			for f in 4: bumps += exp(-pow((x - float(FINGER_X[f]) * side) / .0075, 2.0))
			y += (.0032 + .003 * thin) * smoothstep(.55, 1.0, t) * bumps * s * k
			y += .002 * (1.0 - pow(x / maxf(w, .001), 2.0)) * s
		else:
			y -= .009 * exp(-pow((x - .023 * side) / .012, 2.0)) * exp(-pow((t - .3) / .28, 2.0)) * -s * k
			y -= .005 * exp(-pow((x + .028 * side) / .01, 2.0)) * exp(-pow((t - .45) / .3, 2.0)) * -s * k
			y += .003 * exp(-pow(x / .015, 2.0)) * exp(-pow((t - .5) / .25, 2.0)) * -s * k
		z -= .005 * exp(-pow(x / .022, 2.0)) * smoothstep(.6, 1.0, t)
		var shade := 1.0 - .12 * maxf(0.0, -s) - .1 * smoothstep(.3, 0.0, t)
		return [Vector3(x, y, z), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]


static func _forearm(length: float, flesh: float, side: float, q: int) -> Mesh:
	var key := "arm|%.3f|%.3f|%d|%d" % [length, flesh, side, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [10, 12, 16, 20, 24][q]
	var body: int = [3, 4, 6, 8, 10][q]
	var cap: int = [2, 2, 3, 3, 4][q]
	var rows := body + cap * 2
	var f := func(u: float, v: float) -> Array:
		var i := u * rows
		var t: float
		var z: float
		var k := 1.0
		if i <= cap:
			var a := i / cap * PI * .5
			t = 0.0
			z = -.018 * cos(a) - .004
			k = sin(a)
		elif i >= rows - cap:
			var a := (rows - i) / cap * PI * .5
			t = 1.0
			z = length + .03 * cos(a)
			k = sin(a)
		else:
			t = (i - cap) / body
			z = -.004 + t * (length + .004)
		var grow := smoothstep(0.0, 1.0, pow(t, .6))
		var w := lerpf(.0245, .038, grow) * flesh * k
		var h := lerpf(.0175, .029, grow) * flesh * k
		var th := -v * TAU  # swept away from the fingers: turn the other way to keep the faces outward
		var x := w * cos(th)
		var y := h * sin(th)
		if sin(th) > 0: y += .004 * exp(-pow((x + .019 * side) / .008, 2.0)) * exp(-pow((t - .05) / .07, 2.0)) * sin(th) * k
		var shade := lerpf(1.0, .08, smoothstep(.35, 1.0, t)) * (1.0 - .1 * maxf(0.0, -sin(th)))
		return [Vector3(x, y, z), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]


# ---- the head ----

## opts: mouth ("closed", "none": a smooth blank lower face, "wide": splits back towards the cheeks),
## open (0..1 initial jaw), eyes ("dull": milky eyes deep in the sockets, "hollow": empty sockets),
## skew (0..1: the left eye sits higher, further out and smaller), neck (length of a neck below, m),
## tone, glow, quality.
static func head(opts: Dictionary = {}) -> Node3D:
	var q := tier(opts.get("quality", -1))
	var mouth := String(opts.get("mouth", "closed"))
	var skew := clampf(float(opts.get("skew", 0.0)), 0.0, 1.0)
	var tone: Variant = opts.get("tone", "wax")
	var glow := float(opts.get("glow", 0.0))
	var mat := skin(tone, glow)
	var root := Node3D.new()
	root.name = "HorrorHead"
	var skel := Skeleton3D.new()
	skel.name = "Skull"
	root.add_child(skel)
	skel.add_bone("head")
	skel.add_bone("jaw")
	skel.set_bone_parent(1, 0)
	skel.set_bone_rest(1, Transform3D(Basis(), JAW_PIVOT))
	skel.reset_bone_poses()
	var face := _part(skel, "Face", _head_mesh(mouth, skew, q), mat)
	if not _skins.has("head"): _skins["head"] = skel.create_skin_from_rest_transforms()
	face.skin = _skins["head"]
	face.skeleton = NodePath("..")
	if mouth != "none":
		var cavity := _part(skel, "Mouth", _ellipsoid(Vector3(.05 if mouth == "wide" else .036, .03, .042), q), skin("cavity"))
		cavity.position = Vector3(0, -.044, -.024)
	if String(opts.get("eyes", "dull")) == "dull" and not is_dark(tone):
		for s in [-1.0, 1.0]:
			var c := _socket(s, skew)
			var at: Vector3 = _head_point(c, mouth, skew)[0]
			var eye := _part(skel, "EyeL" if s < 0 else "EyeR", _ellipsoid(Vector3.ONE * .0125 * (1.0 - (.12 * skew if s < 0 else 0.0)), q), skin("eye", glow))
			eye.position = at - c * .0105
	var neck := float(opts.get("neck", 0.0))
	if neck > 0:
		var tube := _part(skel, "Neck", _neck(neck, q), mat)
		tube.position = Vector3(0, -.06, .03)
	root.set_meta("horror_head", {"skeleton": skel, "max": 0.0 if mouth == "none" else (.62 if mouth == "wide" else .4), "mouth": mouth})
	pose_head(root, float(opts.get("open", 0.0)))
	return root


## Open the jaw, 0 shut .. 1 as far as it goes (pure: sets the pose from scratch).
static func pose_head(head_node: Node3D, open: float) -> void:
	var rig: Dictionary = head_node.get_meta("horror_head")
	var skel: Skeleton3D = rig["skeleton"]
	skel.set_bone_pose_rotation(1, Quaternion(Vector3.RIGHT, -clampf(open, 0.0, 1.0) * float(rig["max"])))


static func _socket(s: float, skew: float) -> Vector3:
	var c := Vector3(.42 * s, .12, -.9)
	if s < 0: c += Vector3(-.07, .16, 0) * skew
	return c.normalized()


static func _bump(d: Vector3, c: Vector3, sx: float, sy: float) -> float:
	var dx := d.x - c.x
	var dy := d.y - c.y
	return exp(-(dx * dx / (sx * sx) + dy * dy / (sy * sy))) * smoothstep(.5, .9, d.dot(c))


## The rest shape of the head at unit direction d: [position, shade].
static func _head_point(d: Vector3, mouth: String, skew: float) -> Array:
	var p := Vector3(d.x * .074, d.y * .1, d.z * .094)
	if d.z > 0: p.z *= 1.0 + .08 * d.z * smoothstep(-.6, .3, d.y)
	p.y *= 1.0 - .07 * smoothstep(.6, 1.0, d.y)
	var low := smoothstep(-.15, -.95, d.y)
	var front := smoothstep(-.15, -.6, d.z)
	p.x *= (1.0 + .04 * smoothstep(-.1, .5, d.y)) * (1.0 - .16 * low - .14 * low * front)
	p.y -= .01 * low * low
	p.z *= 1.0 - .1 * low * maxf(0.0, d.z)
	p.z -= .012 * smoothstep(-.55, -.9, d.y) * maxf(0.0, -d.z)
	p.z *= 1.0 - .08 * front * smoothstep(.2, -.2, d.y)
	var push := 0.0
	var shade := 1.0
	for s in [-1.0, 1.0]:
		var size := 1.0 - (.12 * skew if s < 0 else 0.0)
		var g := _bump(d, _socket(s, skew), .18 * size, .13 * size)
		push -= .024 * g * size
		shade *= 1.0 - .95 * pow(g, .5)
		var rim := _bump(d, _socket(s, skew) + Vector3(0, .17, 0), .24, .06)
		push += .007 * rim
		push += .004 * _bump(d, Vector3(.6 * s, -.08, -.78).normalized(), .15, .1)
		var hollow := _bump(d, Vector3(.52 * s, -.36, -.76).normalized(), .17, .14)
		push -= .007 * hollow
		shade *= 1.0 - .25 * hollow
		push -= .004 * _bump(d, Vector3(.86 * s, .28, -.42).normalized(), .2, .2)
		push += .003 * exp(-pow((d.x - s) / .1, 2.0) - pow((d.y + .05) / .2, 2.0)) * exp(-pow(d.z / .25, 2.0))
		shade *= 1.0 - .55 * _bump(d, Vector3(.07 * s, -.31, -.94).normalized(), .035, .03)
	var nose := exp(-pow(d.x / .075, 2.0)) * smoothstep(.12, -.05, d.y) * smoothstep(-.36, -.22, d.y) * front
	push += .012 * nose * smoothstep(.12, -.3, d.y)
	if mouth != "none":
		var wide := mouth == "wide"
		var reach := 1.0 if wide else .3
		var band := .022 if d.y > LIP_Y else .04
		var lip := exp(-pow((d.y - LIP_Y) / band, 2.0)) * smoothstep(reach, reach * .7, absf(d.x)) * front
		shade *= 1.0 - .75 * lip
		# The line sags towards the corners: a slack mouth, never a grin.
		var arc := pow(clampf(absf(d.x) / reach, 0.0, 1.0), 2.0) * exp(-pow((d.y - LIP_Y) / .1, 2.0)) * front
		p.y -= (.003 + .004 * reach) * arc
		push += .002 * exp(-pow((d.y - LIP_Y + .07) / .05, 2.0)) * front * smoothstep(.3, .1, absf(d.x))
	else:
		shade *= 1.0 - .12 * exp(-pow((d.y - LIP_Y) / .08, 2.0)) * front
	shade *= 1.0 - .2 * smoothstep(-.6, -1.0, d.y)
	return [p + d * push, shade]


static func _jaw_weight(d: Vector3) -> float:
	return smoothstep(LIP_Y + .03, LIP_Y - .06, d.y) * smoothstep(.45, -.2, d.z)


static func _head_mesh(mouth: String, skew: float, q: int) -> Mesh:
	var key := "head|%s|%.3f|%d" % [mouth, skew, q]
	if _meshes.has(key): return _meshes[key]
	var rows: int = [22, 28, 36, 44, 52][q]
	var cols: int = [32, 40, 52, 64, 80][q]
	var lip := acos(LIP_Y)
	var lats: Array[float] = []
	for i in rows + 1: lats.append(PI * i / rows)
	var split := -1
	if mouth != "none":
		var best := 0
		for i in range(1, rows):
			if absf(lats[i] - lip) < absf(lats[best] - lip): best = i
		lats[best] = lip
		lats.insert(best + 1, lip)
		split = best
	var half := (1.05 if mouth == "wide" else .36)
	var dir := func(phi: float, th: float) -> Vector3: return Vector3(sin(phi) * sin(th), cos(phi), sin(phi) * cos(th))
	var mouth_w := func(th: float) -> float:
		return 1.0 - smoothstep(half * .8, half, absf(wrapf(th - PI, -PI, PI)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var starts := PackedInt32Array()
	var n := 0
	for i in lats.size():
		var phi: float = lats[i]
		var pole := i == 0 or i == lats.size() - 1
		starts.append(n)
		for j in (1 if pole else cols):
			var th := TAU * j / cols
			var d: Vector3 = dir.call(phi, th)
			var pt: Array = _head_point(d, mouth, skew)
			var w := _jaw_weight(d) if mouth != "none" else 0.0
			var m: float = mouth_w.call(th)
			if i == split: w = lerpf(w, 0.0, m)
			elif i == split + 1: w = lerpf(w, 1.0, m)
			st.set_color(Color(pt[1], pt[1], pt[1]))
			st.set_bones(PackedInt32Array([0, 1, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0 - w, w, 0, 0]))
			st.add_vertex(pt[0])
			n += 1
	for i in lats.size() - 1:
		var a := starts[i]
		var b := starts[i + 1]
		for j in cols:
			var k := (j + 1) % cols
			if i == 0: _tri(st, a, b + k, b + j)
			elif i == lats.size() - 2: _tri(st, a + j, a + k, b)
			elif i == split:
				if mouth_w.call(TAU * j / cols) > .001 or mouth_w.call(TAU * k / cols) > .001: continue
				_tri(st, a + j, a + k, b + k)
				_tri(st, a + j, b + k, b + j)
			else:
				_tri(st, a + j, a + k, b + k)
				_tri(st, a + j, b + k, b + j)
	# The inner lips: short dark flaps turning inwards from both edges of the slit.
	if split >= 0:
		for r in 2:
			var phi: float = lats[split]
			var w0 := 0.0 if r == 0 else 1.0
			var edge := PackedInt32Array()
			var inner := PackedInt32Array()
			for j in cols:
				var th := TAU * j / cols
				var d: Vector3 = dir.call(phi, th)
				var pt: Array = _head_point(d, mouth, skew)
				var m: float = mouth_w.call(th)
				var w := lerpf(_jaw_weight(d), w0, m)
				for layer in 2:
					var at: Vector3 = pt[0] - d * (.009 * layer) + Vector3(0, (.0025 if r == 0 else -.0025) * layer, 0)
					st.set_color(Color.BLACK if layer == 1 else Color(.05, .05, .05))
					st.set_bones(PackedInt32Array([0, 1, 0, 0]))
					st.set_weights(PackedFloat32Array([1.0 - w, w, 0, 0]))
					st.add_vertex(at)
					(edge if layer == 0 else inner).append(n)
					n += 1
			for j in cols:
				var k := (j + 1) % cols
				if mouth_w.call(TAU * j / cols) < .001 and mouth_w.call(TAU * k / cols) < .001: continue
				if r == 0:
					_tri(st, edge[j], edge[k], inner[k])
					_tri(st, edge[j], inner[k], inner[j])
				else:
					_tri(st, edge[j], inner[k], edge[k])
					_tri(st, edge[j], inner[j], inner[k])
	st.generate_normals()
	_meshes[key] = st.commit()
	return _meshes[key]


static func _ellipsoid(radii: Vector3, q: int) -> Mesh:
	var key := "ell|%.4f|%.4f|%.4f|%d" % [radii.x, radii.y, radii.z, q]
	if _meshes.has(key): return _meshes[key]
	var rows: int = [6, 8, 10, 12, 14][q]
	var f := func(u: float, v: float) -> Array:
		var phi := u * PI
		var th := v * TAU
		return [Vector3(sin(phi) * sin(th) * radii.x, cos(phi) * radii.y, sin(phi) * cos(th) * radii.z), 1.0]
	_meshes[key] = _sweep(rows, rows * 2, f)
	return _meshes[key]


static func _neck(length: float, q: int) -> Mesh:
	var key := "neck|%.3f|%d" % [length, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [8, 10, 12, 16, 18][q]
	var body: int = clampi(int(length / .05), 3, [6, 8, 12, 16, 20][q])
	var rows := body + 4
	var f := func(u: float, v: float) -> Array:
		var i := u * rows
		var y: float
		var k := 1.0
		if i <= 2:
			var a := i / 2.0 * PI * .5
			y = .02 * cos(a)
			k = sin(a)
		elif i >= rows - 2:
			var a := (rows - i) / 2.0 * PI * .5
			y = -length - .02 * cos(a)
			k = sin(a)
		else:
			y = -(i - 2) / body * length
		var t := clampf(-y / length, 0.0, 1.0)
		var r := lerpf(.036, .044, t * t) * k
		var th := v * TAU
		var bend := .02 * sin(t * PI) * minf(1.0, length / .4)
		var shade := lerpf(.85, .1, smoothstep(.2, 1.0, t))
		return [Vector3(r * sin(th), y, r * cos(th) * .92 + bend), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]
