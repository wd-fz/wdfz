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
const FINGER_R := [.0096,.0101,.0095,.0084]
const FINGER_YAW := [-.06,0.0,.06,.15]
const FINGER_SPREAD := [-.17,-.045,.09,.23]
const THUMB_LEN := [.04,.032,.027]
const JAW_PIVOT := Vector3(0,-.026,.006)
const LIP_Y := -.43                             # the mouth line, as the y of a unit direction
const TONES := {
	"wax":{"base_color":Color(.47,.45,.41),"vein_color":Color(.4,.46,.5),"deep_color":Color(.25,.16,.18),"vein_amount":.45,"mottle":.16,
		"rim_color":Color(.55,.55,.52),"rim_strength":.45,"rim_emit":.0,"gloss":.1,"shininess":16.0},
	"shadow":{"base_color":Color(.022,.025,.028),"vein_color":Color(.05,.06,.07),"deep_color":Color(0,0,0),"vein_amount":.25,"mottle":.4,
		"rim_color":Color(.45,.47,.48),"rim_strength":.5,"rim_emit":.05,"gloss":.12,"shininess":12.0},
	"nail":{"base_color":Color(.56,.54,.47),"vein_color":Color(.4,.37,.32),"deep_color":Color(.012,.01,.008),"vein_amount":0.0,"mottle":.5,
		"rim_color":Color(.5,.55,.55),"rim_strength":.3,"rim_emit":.02,"gloss":.55,"shininess":50.0,"noise_scale":140.0,"pores":0.0},
	"eye":{"base_color":Color(.5,.53,.5),"vein_color":Color(.4,.44,.44),"deep_color":Color(.03,.03,.03),"vein_amount":0.0,"mottle":.3,
		"rim_color":Color(.5,.58,.6),"rim_strength":.1,"rim_emit":.0,"gloss":.9,"shininess":90.0,"pores":0.0,"smudge":0.0},
	"cavity":{"base_color":Color(.008,.006,.006),"vein_color":Color(.008,.006,.006),"deep_color":Color(0,0,0),"vein_amount":0.0,"mottle":0.0,
		"rim_color":Color(0,0,0),"rim_strength":0.0,"rim_emit":0.0,"gloss":0.0,"shininess":8.0,"pores":0.0,"smudge":0.0},
	"hair":{"base_color":Color(.016,.015,.014),"vein_color":Color(.03,.028,.026),"deep_color":Color(0,0,0),"vein_amount":.6,"mottle":.5,
		"rim_color":Color(.36,.42,.48),"rim_strength":.4,"rim_emit":.04,"rim_power":4.0,"gloss":.0,"shininess":8.0,"noise_scale":260.0,
		"vein_stretch":Vector3(1.0,.12,1.0),"pores":0.0,"smudge":0.0},
}
## A figure's clothes and body: matte, near black, no highlight; only a narrow cold edge shows its volume.
const FIGURE := {"vein_amount":.0,"mottle":.25,"rim_color":Color(.5,.5,.48),"rim_strength":.35,"rim_emit":.0,"rim_power":5.0,
	"gloss":0.0,"shininess":4.0,"wrap":.15,"pores":0.0,"smudge":.5}
const SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec3 base_color : source_color = vec3(.78,.77,.71);
uniform vec3 vein_color : source_color = vec3(.33,.41,.46);
uniform vec3 deep_color : source_color = vec3(.04,.035,.035);
uniform float vein_amount = .2;
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
uniform float pores = 1.0;
uniform float smudge = 1.0;
uniform float cut_y = 1e6;
uniform float ambient_lift = 0.0;
uniform vec3 vein_stretch = vec3(1.0, 1.0, .22);
varying vec3 obj;
float hash(vec3 p) { p = fract(p * .3183099 + .1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { obj = VERTEX; }
void fragment() {
	if (obj.y > cut_y) discard;
	vec3 p = obj * noise_scale * vein_stretch;
	// Veins: thin ridges of a warped noise, stretched along the limb, broken into short branching runs.
	vec3 w = p + vec3(noise(p * .45 + 1.7), noise(p * .45 + 9.2), noise(p * .45 + 4.4)) * 1.8;
	float r1 = 1.0 - abs(noise(w) * 2.0 - 1.0);
	float r2 = 1.0 - abs(noise(w * 2.2 + 5.1) * 2.0 - 1.0);
	float runs = smoothstep(.42, .7, noise(p * .3 + 17.0));
	float vein = (smoothstep(.955, .995, r1) + smoothstep(.965, .997, r2) * .55 * smoothstep(.5, .8, r1)) * runs * vein_amount;
	float blot = noise(p * .17 + 3.0) * .7 + noise(p * .6 + 11.0) * .3 - .5;
	// Pores and grime: a fine speckle and a few dull smears.
	float pore = smoothstep(.7, .95, noise(obj * 700.0)) * .06 * pores;
	float smear = smoothstep(.55, .85, noise(obj * 7.0 + 31.0)) * .22 * smudge;
	// Baked shade is perceptual (like an sRGB value), so darken in linear light by its square-ish.
	float shade = pow(mix(1.0, COLOR.r, vertex_shade), 2.2);
	vec3 skin = mix(base_color, vein_color, clamp(vein + blot * mottle, 0.0, 1.0));
	skin *= (1.0 - pore) * (1.0 - smear);
	ALBEDO = mix(deep_color * clamp(shade * 4.0, 0.0, 1.0), skin, shade);
	ROUGHNESS = .9;
	SPECULAR = .1;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * fres * rim_emit * shade + ALBEDO * (glow + ambient_lift);
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


## Drop every cached mesh, material and the shader (the app and the test runner call it on exit).
static func clear_cache() -> void:
	_meshes.clear()
	_materials.clear()
	_skins.clear()
	_shader = null


# ---- materials ----

## The skin material: a preset name ("wax", "shadow", "nail", "eye", "cavity") or a Color for a tinted
## silhouette (dark colours read as a "shadow" with the rim; light ones as tinted wax). glow adds a
## little self-light so a world prop stays readable in a dark room.
static func skin(tone: Variant = "wax", glow: float = 0.0, vertex_shade: bool = true) -> ShaderMaterial:
	var key := "%s|%.3f|%s" % [str(tone), glow, vertex_shade]
	if _materials.has(key): return _materials[key]
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
	var m := _material(params)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("vertex_shade", 1.0 if vertex_shade else 0.0)
	_materials[key] = m
	return m


static func _material(params: Dictionary) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	for name: String in params: m.set_shader_parameter(name, params[name])
	# Compatibility has no tonemap headroom and a weaker ambient on custom-lit materials: lift the edge
	# and the floor a little so a shadow figure reads like it does on Forward+ and Mobile.
	if _compat():
		m.set_shader_parameter("rim_emit", float(params.get("rim_emit", .05)) * 1.8 + .02)
		m.set_shader_parameter("rim_strength", float(params.get("rim_strength", .55)) * 1.3)
		m.set_shader_parameter("ambient_lift", .05)
	return m


## The head's skin: the same as skin(), but its faint veins run up the temples instead of along a limb.
static func _face_skin(tone: Variant, glow: float) -> ShaderMaterial:
	var key := "face|%s|%.3f" % [str(tone), glow]
	if _materials.has(key): return _materials[key]
	var m := skin(tone, glow).duplicate() as ShaderMaterial
	m.set_shader_parameter("vein_stretch", Vector3(1.0, .3, 1.0))
	m.set_shader_parameter("vein_amount", float(m.get_shader_parameter("vein_amount")) * .5)
	_materials[key] = m
	return m


static func _compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


static func is_dark(tone: Variant) -> bool:
	return (tone is Color and (tone as Color).get_luminance() < .2) or String(str(tone)) in ["shadow", "cavity", "hair"]


## The skin for an imported figure (its baked vertex shades are ignored): matte and near black whatever
## the tint (the tint only colours it faintly), with a narrow cold edge light; nothing glossy or plastic.
## tint: 0 near black (default) .. 1 keeps the colour as given. cut_y: fragments of the figure's own mesh
## above this height (its local metres, feet at 0) are not drawn, so a HorrorKit head can take its place.
static func figure_skin(col: Color, tint: float = 0.0, cut_y: float = INF) -> ShaderMaterial:
	if col.get_luminance() < .12:
		col = Color("2a3445")  # a black body is a hole: dress it as a school uniform and keep that colour
		tint = 1.0
	var key := "fig|%s|%.3f|%.3f" % [col.to_html(), tint, minf(cut_y, 1e6)]
	if _materials.has(key): return _materials[key]
	var params: Dictionary = FIGURE.duplicate()
	var lum := maxf(col.get_luminance(), .001)
	var dark := col * minf(1.0, .03 / lum)
	dark.a = 1.0
	params["base_color"] = dark.lerp(col, clampf(tint, 0.0, 1.0))
	params["vein_color"] = (params["base_color"] as Color).darkened(.3)
	params["deep_color"] = Color(0, 0, 0)
	params["cut_y"] = minf(cut_y, 1e6)
	var m := _material(params)
	m.set_shader_parameter("vertex_shade", 0.0)
	_materials[key] = m
	return m


static func dress(node: Node, mat: Material) -> void:
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---- the hand ----

## opts: long (finger length multiplier, 1.1: a little too long), extra (a fourth phalanx on each finger),
## thin (0..1, bony: thinner skin, bigger knuckles), arm (forearm length, m), side (1 right, -1 mirrored),
## tone (skin preset or Color), glow, nails (true), fade (Vector2: where along the forearm, 0 wrist .. 1 elbow,
## it starts and finishes darkening into nothing; default (.35, 1)), quality (tier).
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
	_part(root, "Forearm", _forearm(float(opts.get("arm", .26)), flesh, side, q, opts.get("fade", Vector2(.35, 1.0))), mat)
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
		else: angles = [c * 1.45, c * 1.65, c * 1.0]
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
	# Every joint is one sphere shared by the two phalanges that meet there (same centre, same radius),
	# so a bent finger stays one smooth surface; the knuckle is a bony swell on the back of that sphere.
	var radius := func(j: int) -> float: return r * (1.0 - .24 * float(j) / maxf(1, n - 1))
	for j in n:
		var joint := Node3D.new()
		joint.name = "J%d" % j
		if j > 0: joint.position = Vector3(0, 0, -float(lengths[j - 1]))
		parent.add_child(joint)
		var tip := j == n - 1
		var r0: float = radius.call(j)
		var r1: float = r0 * .8 if tip else radius.call(j + 1)
		var knuckle := 0.0 if tip else r * (.1 + .22 * thin) * (1.0 - .35 * float(j) / maxf(1, n - 1))
		_part(joint, "Knuckle", _ellipsoid(Vector3.ONE * r0 * 1.06, q), mat)
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


static func _phalanx_r(s: float, length: float, r0: float, r1: float, _knuckle: float = 0.0) -> float:
	var t := clampf(s / length, 0.0, 1.0)
	# Slimmer in the middle of the bone than at either joint.
	return lerpf(r0, r1, t) * (1.0 - .07 * sin(t * PI))


## One phalanx along -Z from its joint: a sphere of radius r0 centred on its own joint, one of r1 on the
## next (the next phalanx starts with exactly that sphere), a waist between; a bony knuckle on the back of
## the far joint, creases darker on both sides of each joint; the last one tapers to a darkened fingertip.
static func _phalanx(length: float, r0: float, r1: float, knuckle: float, tip: bool, q: int) -> Mesh:
	var key := "ph2|%.5f|%.5f|%.5f|%.5f|%s|%d" % [length, r0, r1, knuckle, tip, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [6, 8, 10, 12, 14][q]
	var body: int = [3, 4, 5, 6, 7][q]
	var cap: int = [2, 3, 3, 4, 5][q]
	var rows := body + cap * 2
	var ce := r1 * (1.5 if tip else 1.0)
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
			r = r1 * sin(a)
		else:
			s = (i - cap) / body * length
			r = _phalanx_r(s, length, r0, r1)
		var th := v * TAU
		var up := sin(th)
		var flat := .86 if not tip else lerpf(.86, .72, smoothstep(length * .3, length + ce, s))
		var at := Vector3(r * cos(th), r * up * flat, -s)
		# The knuckle: a swell on the back of the far joint, leaning forward so a bent finger shows it.
		if knuckle > 0:
			var dorsal := maxf(0.0, up)
			at.y += knuckle * dorsal * dorsal * exp(-pow((s - length - r1 * .25) / (r1 * 1.1), 2.0))
		var crease := exp(-pow(s / (r0 * .9), 2.0)) + exp(-pow((s - length) / (r1 * .9), 2.0)) * (0.0 if tip else 1.0)
		var shade := 1.0 - .2 * maxf(0.0, -up) * crease - .1 * maxf(0.0, up) * crease * (1.0 - maxf(0.0, up))
		if tip:
			var tt := clampf((s - length * .4) / (length * .6 + ce), 0.0, 1.0)
			shade *= lerpf(1.0, .45, tt * tt)
			if up > .2 and s > length * .38: shade *= .75
		return [at, shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]


## The nail: a curved plate over the top of the last phalanx; its free edge and folds are dark.
static func _nail(length: float, r0: float, r1: float, q: int) -> Mesh:
	var key := "nail2|%.5f|%.5f|%.5f|%d" % [length, r0, r1, q]
	if _meshes.has(key): return _meshes[key]
	var ce := r1 * 1.5
	var rows: int = [3, 4, 5, 6, 7][q]
	var cols: int = [3, 4, 5, 6, 6][q]
	var f := func(u: float, v: float) -> Array:
		var s := lerpf(length * .4, length + ce * .66, u)
		var r: float
		if s <= length: r = _phalanx_r(s, length, r0, r1)
		else: r = r1 * sin(acos(clampf((s - length) / ce, 0.0, 1.0)))
		var flat := lerpf(.86, .72, smoothstep(length * .3, length + ce, s))
		var th := PI * .5 + (v - .5) * 1.85
		var edge := absf(v - .5) * 2.0
		# The nail bed: a dull plate, its fold and sides sunk dark; the free edge black with grime.
		var shade := .82 - .5 * smoothstep(.55, 1.0, edge) - .5 * smoothstep(.2, 0.0, u) + .08 * smoothstep(.15, .35, u) * (1.0 - smoothstep(.35, .55, u))
		shade = lerpf(shade, .03, smoothstep(.68, .9, u))
		r += .0005 + .0004 * u
		return [Vector3(r * cos(th) * .97, r * sin(th) * flat + .0002, -s), shade]
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


static func _forearm(length: float, flesh: float, side: float, q: int, fade: Vector2 = Vector2(.35, 1.0)) -> Mesh:
	var key := "arm|%.3f|%.3f|%d|%d|%.2f|%.2f" % [length, flesh, side, q, fade.x, fade.y]
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
		var shade := lerpf(1.0, .04, smoothstep(fade.x, fade.y, t)) * (1.0 - .1 * maxf(0.0, -sin(th)))
		return [Vector3(x, y, z), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]


# ---- the head ----

## opts: mouth ("closed", "none": a smooth blank lower face, "wide": splits back towards the cheeks),
## open (0..1 initial jaw), eyes ("dull": milky eyes deep in the sockets, "hollow": empty sockets),
## socket (.3..1: eye socket depth, 1 default), skew (0..1: the left eye sits higher, further out and smaller), neck (length of a neck below, m),
## hair (false: short black hair over the crown, back and sides), tone, glow, quality.
static func head(opts: Dictionary = {}) -> Node3D:
	var q := tier(opts.get("quality", -1))
	var mouth := String(opts.get("mouth", "closed"))
	var skew := clampf(float(opts.get("skew", 0.0)), 0.0, 1.0)
	var socket := clampf(float(opts.get("socket", 1.0)), .3, 1.0)  # how deep the eye sockets are (1 the default)
	var tone: Variant = opts.get("tone", "wax")
	var glow := float(opts.get("glow", 0.0))
	var mat := _face_skin(tone, glow)
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
	var face := _part(skel, "Face", _head_mesh(mouth, skew, q, socket), mat)
	if not _skins.has("head"): _skins["head"] = skel.create_skin_from_rest_transforms()
	face.skin = _skins["head"]
	face.skeleton = NodePath("..")
	if mouth != "none":
		var cavity := _part(skel, "Mouth", _ellipsoid(Vector3(.05 if mouth == "wide" else .036, .03, .042), q), skin("cavity"))
		cavity.position = Vector3(0, -.044, -.024)
	if String(opts.get("eyes", "dull")) == "dull" and not is_dark(tone):
		for s in [-1.0, 1.0]:
			var c := _socket(s, skew)
			var at: Vector3 = _head_point(c, mouth, skew, socket)[0]
			var eye := _part(skel, "EyeL" if s < 0 else "EyeR", _ellipsoid(Vector3.ONE * .0125 * (1.0 - (.12 * skew if s < 0 else 0.0)), q), skin("eye", glow))
			eye.position = at - c * .0105
	var neck := float(opts.get("neck", 0.0))
	if neck > 0:
		var tube := _part(skel, "Neck", _neck(neck, q), mat)
		tube.position = Vector3(0, -.06, .03)
	if bool(opts.get("hair", false)):
		_part(skel, "Hair", _hair_mesh(mouth, skew, q, socket), skin("hair", glow * .3))
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


static func _blob(d: Vector3, c: Vector3, sx: float, sy: float, sz: float) -> float:
	var e := d - c
	return exp(-(e.x * e.x / (sx * sx) + e.y * e.y / (sy * sy) + e.z * e.z / (sz * sz)))


## The rest shape of the head at unit direction d: [position, shade]. An ordinary skull (a low crown, a
## jaw nearly as wide as the cheeks, cheekbones, a nose with a bridge, a philtrum, a chin, plain ears);
## only the sockets are too deep and the mouth is wrong.
static func _head_point(d: Vector3, mouth: String, skew: float, socket: float = 1.0) -> Array:
	var p := Vector3(d.x * .075, d.y * .104, d.z * .095)
	if d.z > 0: p.z *= 1.0 + .07 * d.z * smoothstep(-.6, .3, d.y)
	p.y *= 1.0 - .13 * smoothstep(.5, 1.0, d.y)
	var low := smoothstep(-.15, -.95, d.y)
	var front := smoothstep(-.15, -.6, d.z)
	p.x *= (1.0 + .015 * smoothstep(-.1, .5, d.y)) * (1.0 - .07 * low - .1 * low * front)
	p.y -= .012 * low * low
	p.z *= 1.0 - .1 * low * maxf(0.0, d.z)
	p.z -= .012 * smoothstep(-.55, -.9, d.y) * maxf(0.0, -d.z)
	p.z *= 1.0 - .06 * front * smoothstep(.2, -.2, d.y)
	# A flatter, more upright forehead.
	p.z *= 1.0 - .05 * front * smoothstep(.15, .6, d.y) * smoothstep(1.0, .7, d.y)
	var push := 0.0
	var shade := 1.0
	for s in [-1.0, 1.0]:
		var size := 1.0 - (.12 * skew if s < 0 else 0.0)
		var g := _bump(d, _socket(s, skew), .17 * size, .12 * size)
		push -= .024 * g * size * socket
		shade *= 1.0 - .95 * pow(g, .5) * socket
		var rim := _bump(d, _socket(s, skew) + Vector3(0, .16, 0), .22, .055)
		push += .006 * rim
		# Cheekbones, the hollow under them, the jaw angle, the temple.
		push += .005 * _blob(d, Vector3(.66 * s, -.12, -.74).normalized(), .2, .1, .22)
		var hollow := _bump(d, Vector3(.55 * s, -.4, -.74).normalized(), .15, .12)
		push -= .004 * hollow
		shade *= 1.0 - .2 * hollow
		push += .004 * _blob(d, Vector3(.78 * s, -.6, -.05).normalized(), .26, .18, .28)
		push -= .004 * _bump(d, Vector3(.86 * s, .28, -.42).normalized(), .2, .2)
		# An ear: a flat plate standing out at the side, behind the jaw; dark in its bowl and behind it.
		var ear := _blob(d, Vector3(.98 * s, -.16, .16).normalized(), .2, .26, .1)
		push += .015 * ear
		shade *= 1.0 - .35 * _blob(d, Vector3(.99 * s, -.14, .2).normalized(), .1, .12, .05) - .25 * _blob(d, Vector3(.9 * s, -.16, .38).normalized(), .2, .24, .06)
		# Nostrils.
		push += .004 * _blob(d, Vector3(.08 * s, -.27, -.96).normalized(), .05, .04, .2)
		shade *= 1.0 - .55 * _bump(d, Vector3(.045 * s, -.3, -.95).normalized(), .025, .02)
	# The nose: a bridge from between the eyes to a rounded tip, short underneath.
	var ridge := exp(-pow(d.x / lerpf(.05, .085, smoothstep(.05, -.25, d.y)), 2.0)) * smoothstep(.16, .06, d.y) * smoothstep(-.33, -.25, d.y) * front
	push += ridge * (.004 + (.016 if mouth == "wide" else .019) * smoothstep(.06, -.25, d.y))
	shade *= 1.0 - .15 * exp(-pow(d.x / .09, 2.0)) * exp(-pow((d.y + .33) / .03, 2.0)) * front
	# The philtrum: a shallow groove from the nose to the upper lip.
	var phil := exp(-pow(d.x / .028, 2.0)) * smoothstep(-.31, -.34, d.y) * smoothstep(LIP_Y - .01, LIP_Y + .04, d.y) * front
	push -= .0015 * phil
	shade *= 1.0 - .12 * phil
	# The chin.
	push += .008 * _blob(d, Vector3(0, -.78, -.62).normalized(), .2, .14, .2)
	if mouth != "none":
		var wide := mouth == "wide"
		var reach := 1.0 if wide else .3
		var band := .02 if d.y > LIP_Y else (.022 if wide else .03)
		var lip := exp(-pow((d.y - LIP_Y) / band, 2.0)) * smoothstep(reach, reach * .7, absf(d.x)) * front
		shade *= 1.0 - .6 * lip
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


static func _head_mesh(mouth: String, skew: float, q: int, socket: float = 1.0) -> Mesh:
	var key := "head|%s|%.3f|%d|%.2f" % [mouth, skew, q, socket]
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
			var pt: Array = _head_point(d, mouth, skew, socket)
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
				var pt: Array = _head_point(d, mouth, skew, socket)
				var m: float = mouth_w.call(th)
				var w := lerpf(_jaw_weight(d), w0, m)
				for layer in 2:
					var at: Vector3 = pt[0] - d * (.009 * layer) + Vector3(0, (.0025 if r == 0 else -.0025) * layer, 0)
					if mouth == "wide":
						# Lips of skin (a shade darker than the face); only the deep corners of the mouth go dark.
						var corner := smoothstep(.45, 1.0, absf(wrapf(th - PI, -PI, PI)) / half)
						st.set_color(Color(.62, .62, .62) if layer == 0 else Color.WHITE * lerpf(.3, .02, corner))
					else:
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


## Short hair: a shell over the crown, the back and the sides, sunk under the skin below the hairline.
static func _hair_mesh(mouth: String, skew: float, q: int, socket: float = 1.0) -> Mesh:
	var key := "hair|%s|%.3f|%d|%.2f" % [mouth, skew, q, socket]
	if _meshes.has(key): return _meshes[key]
	var rows: int = [20, 26, 34, 42, 50][q]
	var f := func(u: float, v: float) -> Array:
		var phi := u * PI
		var th := v * TAU
		var d := Vector3(sin(phi) * sin(th), cos(phi), sin(phi) * cos(th))
		var line := lerpf(.4, -.55, smoothstep(-.75, .75, d.z))
		# Clear of the ears; a short fringe dips over the middle of the forehead.
		line = maxf(line, .12 * smoothstep(.7, .9, absf(d.x)) * smoothstep(.5, .05, d.z))
		line -= .075 * exp(-pow(d.x / .35, 2.0)) * smoothstep(-.4, -.8, d.z)
		# A ragged edge instead of a bowl rim.
		line += (.018 * sin(th * 7.0) + .012 * sin(th * 13.0)) * smoothstep(.9, .3, d.y)
		var h := d.y - line
		var grow := smoothstep(-.03, .12, h)
		var thick := lerpf(-.003, .0065 + .003 * smoothstep(.6, 1.0, d.y), grow)
		# The unskinned shell must not show through an open mouth: below the face's hairline it sinks deep into the skull.
		thick -= .03 * smoothstep(0.0, -.25, d.y) * smoothstep(.3, -.2, d.z) * (1.0 - grow)
		var at: Vector3 = _head_point(d, mouth, skew, socket)[0]
		return [at + d * thick, lerpf(.4, 1.0, grow)]
	_meshes[key] = _sweep(rows, rows * 2, f)
	return _meshes[key]


## A head on a neck and shoulders (a figure seen from the chest up), its origin at the middle of the
## skull like head(). opts: all of head()'s, plus body (how far the chest runs down below the shoulders,
## fading into the dark, m) and cloth (the clothes' colour; matte and near black like figure_skin).
static func bust(opts: Dictionary = {}) -> Node3D:
	var q := tier(opts.get("quality", -1))
	var root := Node3D.new()
	root.name = "HorrorBust"
	var hopts := opts.duplicate()
	hopts.erase("neck")
	var hd := head(hopts)
	root.add_child(hd)
	var neck := _part(root, "BustNeck", _neck(float(opts.get("neck", .1)), q, 1.35), _face_skin(opts.get("tone", "wax"), float(opts.get("glow", 0.0))))
	neck.position = Vector3(0, -.065, .025)
	var body := float(opts.get("body", .35))
	var cloth := _cloth(opts.get("cloth", Color(.05, .055, .06)))
	var torso := _part(root, "Torso", _torso(body, q), cloth)
	torso.position = Vector3(0, -.165, .03)
	if opts.has("collar"):
		# A shirt collar: a flat ring round the base of the neck.
		var ring := TorusMesh.new()
		ring.inner_radius = .054
		ring.outer_radius = .07
		ring.rings = 16
		ring.ring_segments = 6
		var collar := _part(root, "Collar", ring, _cloth(opts["collar"]))
		collar.position = Vector3(0, -.148, .03)
		collar.scale = Vector3(1, .5, 1)
	root.set_meta("horror_bust", {"head": hd, "torso": torso})
	return root


static func _cloth(col: Color) -> ShaderMaterial:
	var key := "cloth|%s" % col.to_html()
	if _materials.has(key): return _materials[key]
	var params: Dictionary = FIGURE.duplicate()
	params["base_color"] = col
	params["vein_color"] = col.darkened(.3)
	params["deep_color"] = Color(0, 0, 0)
	var m := _material(params)
	_materials[key] = m
	return m


## Shoulders and chest below a neck at the origin: the collar, the slope of the shoulders, the arms' tops,
## then straight down for length metres, darkening to nothing.
static func _torso(length: float, q: int) -> Mesh:
	var key := "torso|%.3f|%d" % [length, q]
	if _meshes.has(key): return _meshes[key]
	var seg: int = [12, 14, 18, 22, 26][q]
	var rows: int = [6, 8, 10, 12, 14][q]
	var f := func(u: float, v: float) -> Array:
		var y: float
		var hw: float
		var hd: float
		var k := 1.0
		if u < .12:
			var a := u / .12
			y = .02 - .01 * a
			hw = .05 * a + .001
			hd = .045 * a + .001
		elif u < .45:
			var a := (u - .12) / .33
			var e := sin(a * PI * .5)
			y = .01 - .1 * a
			hw = lerpf(.05, .185, e)
			hd = lerpf(.045, .1, e)
		else:
			var a := (u - .45) / .55
			y = -.09 - length * a
			hw = lerpf(.185, .17, a)
			hd = lerpf(.1, .095, a)
			k = 1.0 - a
		var th := -v * TAU  # swept downwards: turn this way to keep the faces outward
		var c := cos(th)
		var sn := sin(th)
		var x := hw * signf(c) * pow(absf(c), .8)
		var z := hd * sn
		# The shoulders slope down towards the arms.
		var drop := .05 * pow(absf(c), 3.0) * smoothstep(.12, .45, u)
		return [Vector3(x, y - drop, z), clampf(k * 1.4, 0.0, 1.0)]
	_meshes[key] = _sweep(rows, seg, f)
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


static func _neck(length: float, q: int, girth: float = 1.0) -> Mesh:
	var key := "neck|%.3f|%d|%.2f" % [length, q, girth]
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
		var r := lerpf(.036, .044, t * t) * k * girth
		var th := v * TAU
		var bend := .02 * sin(t * PI) * minf(1.0, length / .4)
		var shade := lerpf(.85, .1, smoothstep(.2, 1.0, t))
		if girth > 1.0:
			# A bust's neck shows through an open mouth: its top, up inside the jaw, is slim and in shadow.
			r *= lerpf(.6, 1.0, smoothstep(.0, .4, t))
			shade *= lerpf(.1, 1.0, smoothstep(.1, .45, t))
		return [Vector3(r * sin(th), y, r * cos(th) * .92 + bend), shade]
	_meshes[key] = _sweep(rows, seg, f)
	return _meshes[key]
