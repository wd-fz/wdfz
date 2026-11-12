class_name DeathStage
extends Node
## Presentation-only stage. Local +z is forward; origin is the player's feet.
## Owns camera/world visibility and restores their complete state on every exit.

const LIFT_SEG := {"a": [0.0, 0.045, 0.05, 0.01], "b": [0.025, 0.0225, 0.01, 0.045], "c": [0.025, -0.0225, 0.01, 0.045], "d": [0.0, -0.045, 0.05, 0.01],
	"e": [-0.025, -0.0225, 0.01, 0.045], "f": [-0.025, 0.0225, 0.01, 0.045], "g": [0.0, 0.0, 0.05, 0.01]}
const LIFT_DIGIT := {1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd"}


var on := false
## Live deaths keep their surroundings; archives and previews author their own sets.
var live_scene := false
var fx := ""
var k := 0.0
var dur := 3.0
var F: Node3D
var cam: Camera3D
var veil_mesh: MeshInstance3D
var shk := 1.0
var rand := RandomNumberGenerator.new()
var _original_random_state := 7
var d: Dictionary = {}                 # per-scene state
var _player: PlayerController
var _world: Node3D
var _world_was_visible := true
var _sky: MeshInstance3D
var _camera_transform := Transform3D.IDENTITY
var _camera_fov := 75.0
var _camera_near := 0.05
var _base_pitch := 0.0
var _base_y := 0.0
var _cued := {}
var _flashed := {}
var _fx_cache := {}
var _ui: GameUI
var _restored := true
var sound_output: Callable
var audio: AudioFx  ## set by the caller; the beat sounds of the scenes (SFX.door, sting, ...) go through it
var stage_lights: Array[Light3D] = []  ## key and motivated lights of the stage; freed by _restore wherever they hang
var _env_owned := false
var _env_previous: Environment


static func seg(kk: float, a: float, b: float) -> float:
	return 0.0 if kk <= a else (1.0 if kk >= b else (kk - a) / (b - a))


static func ss(kk: float, a: float, b: float) -> float:
	var x := seg(kk, a, b)
	return x * x * (3.0 - 2.0 * x)


func begin(cause: String, player: PlayerController, world: Node3D, ui: GameUI, duration: float, reduce_shake: bool = false, camera_override: Camera3D = null, live: bool = false) -> void:
	_restore()
	_restored = false
	live_scene = live
	d.clear()
	_cued.clear()
	_flashed.clear()
	_lift = 0.0
	fx = cause
	dur = duration
	k = 0.0
	on = true
	_player = player
	_world = world
	_world_was_visible = world.visible
	_ui = ui
	cam = player.camera if camera_override == null else camera_override
	shk = 0.0 if reduce_shake else 1.0
	rand.seed = hash(cause)
	_original_random_state = 7
	for ch in cause.length():
		_original_random_state = (_original_random_state*31+cause.unicode_at(ch))&0xffffffff
	_camera_transform = cam.transform
	_camera_fov = cam.fov
	_camera_near = cam.near
	_base_pitch = cam.rotation.x
	_base_y = cam.position.y
	F = Node3D.new()
	F.name = "DeathFrame"
	F.rotation_order = EULER_ORDER_YXZ
	player.get_parent().add_child(F)
	F.global_position = Vector3(player.global_position.x, player.global_position.y, player.global_position.z)
	F.rotation.y = player.rotation.y + PI          # local +z = the gaze
	veil_mesh = null
	_build_scene()
	update(0.0)


func _exit_tree() -> void:
	_restore()


func _restore() -> void:
	if _restored:
		return
	_restored = true
	if _ui != null and is_instance_valid(_ui):
		_ui.cut_flash(0)
	if cam != null and is_instance_valid(cam):
		cam.transform = _camera_transform
		cam.fov = _camera_fov
		cam.near = _camera_near
		if is_instance_valid(veil_mesh):
			veil_mesh.hide()
			veil_mesh.queue_free()
	veil_mesh = null
	if _world != null and is_instance_valid(_world):
		_world.visible = _world_was_visible
	if F != null and is_instance_valid(F):
		F.hide()
		F.queue_free()
	F = null
	if _sky != null and is_instance_valid(_sky):
		_sky.hide()
		_sky.queue_free()
	_sky = null
	for light in stage_lights:
		if is_instance_valid(light):
			light.hide()
			light.queue_free()
	stage_lights.clear()
	if _env_owned:
		if cam != null and is_instance_valid(cam): cam.environment = _env_previous
		_env_owned = false
	_env_previous = null


func tick(delta: float) -> void:
	if not on:
		return
	k += delta
	update(k)
	if k >= dur:
		finish()


func finish() -> void:
	if not on:
		return
	on = false
	_restore()


# ---- helpers (the old Ctx) ----

func _mat(col: Color, op: float = -1.0, double: bool = false, over: bool = false, fog_enabled: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col if op < 0.0 else Color(col.r, col.g, col.b, op)
	m.disable_fog = not fog_enabled
	if op >= 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if over:
		m.no_depth_test = true
		m.render_priority = 100
	return m


## Lit counterpart of _mat for the newer sets: per-pixel shading, matte, fogged into the stage dark.
## The stage lights (key_light / motive_light) and stage_dark's ambient decide what is seen.
func _mat_lit(col: Color, op: float = -1.0, double: bool = false, rough: float = .9, fog_enabled: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col if op < 0.0 else Color(col.r, col.g, col.b, op)
	m.roughness = rough
	m.metallic_specular = .3
	m.disable_fog = not fog_enabled
	if op >= 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The stage's own darkness: overrides the camera's environment (restored by _restore) with a dim
## ambient and an exponential fog of the background colour, so distance falls into black. Post effects
## of the current environment (glow, SSAO, tonemap) are kept; GI that would read the hidden world is off.
func stage_dark(fog: Color = Color(.012, .016, .02), density: float = .085, ambient: Color = Color(.27, .26, .24), ambient_energy: float = .6) -> Environment:
	if not _env_owned:
		_env_previous = cam.environment
		_env_owned = true
	var base := _env_previous
	if base == null and cam.get_world_3d() != null:
		base = cam.get_world_3d().environment if cam.get_world_3d().environment != null else cam.get_world_3d().fallback_environment
	var e: Environment = base.duplicate() if base != null else Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = fog
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = fog
	e.fog_light_energy = 1.0
	e.fog_density = density
	e.fog_sun_scatter = 0.0
	e.fog_aerial_perspective = 0.0
	e.fog_sky_affect = 1.0
	e.fog_height_density = 0.0
	e.volumetric_fog_enabled = false
	e.sdfgi_enabled = false
	e.ssil_enabled = false
	cam.environment = e
	return e


## The stage's key light: a cold spot from at towards aim (stage-local, or parent-local). No shadows.
func key_light(at: Vector3, aim: Vector3, col: Color = Color(.72, .82, .9), energy: float = 2.4, reach: float = 9.0, angle: float = 46.0, parent: Node3D = null) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.name = "StageKey"
	l.light_color = col
	l.light_energy = energy
	l.light_specular = .35
	l.spot_range = reach
	l.spot_angle = angle
	l.spot_attenuation = 1.2
	l.spot_angle_attenuation = .5  # a soft, centre-weighted beam: no hard torch circle on the walls
	l.shadow_enabled = false
	put(l, at.x, at.y, at.z, parent)
	var dir := aim - at
	if dir.length_squared() > 1e-6:
		l.basis = Basis.looking_at(dir, Vector3.UP if absf(dir.normalized().y) < .99 else Vector3.BACK)
	stage_lights.append(l)
	return l


## A motivated light (a tube, a lamp, a window, a screen): an omni pool at at.
func motive_light(at: Vector3, col: Color = Color(.85, .9, .86), energy: float = 1.2, reach: float = 4.0, parent: Node3D = null) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "StageMotive"
	l.light_color = col
	l.light_energy = energy
	l.light_specular = .25
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	put(l, at.x, at.y, at.z, parent)
	stage_lights.append(l)
	return l


func put(n: Node3D, x: float, y: float, z: float, parent: Node3D = null) -> Node3D:
	n.position = Vector3(x, y, z)
	(parent if parent != null else F).add_child(n)
	return n


func mesh(m: Mesh, mat: Material, x: float, y: float, z: float, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.rotation_order = EULER_ORDER_XYZ
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	put(mi, x, y, z, parent)
	return mi


func box(w: float, h: float, dd: float, col: Color, op: float, x: float, y: float, z: float, fog_enabled: bool = true) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, dd)
	return mesh(bm, _mat(col, op,false,false,fog_enabled), x, y, z)


func torus(radius: float, tube: float, mat: Material, x: float, y: float, z: float, parent: Node3D = null, radial: int = 6, tubular: int = 24) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = radius - tube
	tm.outer_radius = radius + tube
	tm.rings = tubular
	tm.ring_segments = radial
	return mesh(_turned_mesh(tm,Basis(Vector3.RIGHT,PI/2)),mat,x,y,z,parent)


## A figure of the old build (front +z, the old rotations apply). lit: shaded by the stage lights
## with HorrorKit's figure skin (a dark tint becomes a rim-lit shadow); drawn over everything, it stays unlit.
func fig(kind: String, col: Color, scale: float, x: float, z: float, over: bool = false, lit: bool = false) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_YXZ
	var fm := FigureModel.make(kind, col, not lit or over, scale)
	if lit and not over: HorrorKit.dress(fm, HorrorKit.figure_skin(col))
	fm.rotation.y = PI
	g.add_child(fm)
	if over:
		for mi: Node in fm.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m != null:
				m.no_depth_test = true
				m.render_priority = 101
	put(g, x, 0.0, z)
	return g


## A "thing" of the old fxMesh (hand, head, bigface, smile, neckhead, bell), front +z.
func fxm(name: String, scale: float, x: float, y: float, z: float) -> Node3D:
	var g := Node3D.new()
	g.rotation_order = EULER_ORDER_YXZ
	var path := "res://assets/campus/fx/%s.glb" % name
	if ResourceLoader.exists(path):
		if not _fx_cache.has(name):
			_fx_cache[name] = load(path)
		var inst := (_fx_cache[name] as PackedScene).instantiate() as Node3D
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = false
		for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(inst)
	g.scale = Vector3.ONE * scale
	put(g, x, y, z)
	return g


## The closing: a sphere over the camera, drawn over everything.
func veil(col: Color) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	veil_mesh = MeshInstance3D.new()
	veil_mesh.name = "DeathVeil"
	veil_mesh.mesh = sm
	veil_mesh.material_override = _mat(col, 0.0, false, true, false)
	(veil_mesh.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_FRONT
	cam.add_child(veil_mesh)


func shade(v: float) -> void:
	if veil_mesh != null:
		var m := veil_mesh.material_override as StandardMaterial3D
		m.albedo_color.a = minf(0.94, v)


## Hide the scene itself; only the props of the scene are seen, against a dark sky.
func hide_world(sky: Color = Color(0.02, 0.025, 0.03)) -> void:
	_world_was_visible = _world.visible
	_world.visible = false
	_sky = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 60.0
	sm.height = 120.0
	_sky.mesh = sm
	var m := _mat(sky,-1,false,false,false)
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	_sky.material_override = m
	cam.add_child(_sky)


## Many small things drawn at once: a MultiMesh of count instances, placed each frame with set_i.
func inst(m: Mesh, mat: Material, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	put(mi, 0.0, 0.0, 0.0)
	return mi


## Place instance i; a scale of 0 hides it.
func set_i(im: MultiMeshInstance3D, i: int, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	im.multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(rot, EULER_ORDER_XYZ)*Basis.from_scale(scl), pos))


func _original_random() -> float:
	_original_random_state = (_original_random_state*1664525+1013904223)&0xffffffff
	return _original_random_state/4294967296.0


func _turned_mesh(shape: Mesh, turn: Basis) -> ArrayMesh:
	var arrays := shape.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		vertices[i] = turn*vertices[i]
		if i<normals.size(): normals[i] = turn*normals[i]
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	# The affected primitives are untextured; stale tangents must not survive a basis change.
	arrays[Mesh.ARRAY_TANGENT] = null
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result


func disc(radius: float, col: Color, op: float, x: float, y: float, z: float, sides: int = 24, fog_enabled: bool = true) -> MeshInstance3D:
	# Original CircleGeometry is flat in XY; the caller supplies its floor/ceiling/facing rotation.
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.BACK])
	var indices := PackedInt32Array()
	for i in range(sides+1):
		vertices.append(Vector3(cos(i*TAU/sides)*radius,sin(i*TAU/sides)*radius,0))
		normals.append(Vector3.BACK)
		if i>0: indices.append_array([0,i+1,i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh(shape,_mat(col,op,true,false,fog_enabled),x,y,z)


func cam_y() -> float:
	return _base_y + _lift


var _lift := 0.0


## The camera: relative to the gaze at death; the first 0.4 s goes over from the player's own pitch.
func view(kk: float, dang: float, pitch: float, lift: float) -> void:
	_lift = lift
	cam.rotation = Vector3(clampf(pitch + _base_pitch * (1.0 - ss(kk, 0.0, 0.4)), -1.45, 1.45), -dang, 0.0)
	cam.position.y = _base_y + lift


## One beat sound (the old SFX.* calls inside the scenes). Silent when no audio is attached (tests).
func snd(sound_id: String, opts: Dictionary = {}) -> void:
	if sound_output.is_valid():
		sound_output.call(sound_id, opts)
	elif audio != null and is_instance_valid(audio):
		audio.play(sound_id, opts)


func cue(id: String, kk: float, at: float, fn: Callable) -> void:
	if kk >= at and not _cued.has(id):
		_cued[id] = true
		fn.call()


func update(kk: float) -> void:
	if on:
		_present_scene(kk)


func _build_scene() -> void:
	pass


func _present_scene(_time: float) -> void:
	pass
