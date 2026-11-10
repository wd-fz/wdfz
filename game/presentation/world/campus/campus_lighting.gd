class_name CampusLighting
extends Node3D
## Presentation port of the Web version's lighting (reference wd-fz.github.io@0bf508a): lighting.js
## (sunAt, skyRGB, lightState, updateLighting, roomFlicker, lampHealth, dyingTube, lampTick) and
## engine/scene.js addRoomLights with content/scene-data.js ROOM_LIGHTS. Reads the game clock only;
## never writes game state. Three.js physical light units are mapped by fixed factors (see ENERGY_*).

const SKY_NIGHT := ["#03060a", "#070c11", "#0c141a", "#111b22"]
const SKY_DAY := ["#4f5961", "#66707a", "#848c93", "#9aa0a3"]
const SKY_GOLD := ["#2a2f3c", "#4c4852", "#7d6559", "#94776a"]
const MOON_DIR := Vector3(-0.42, 0.80, 0.43)
## three.js candela (decay 2) -> Godot omni energy; ambient / directional radiance -> energy.
const ENERGY_POINT := 1.0 / 14.0
## Render layer of the first-person hands: they are lit by the ambient and their own fill light only (hands.js drew them in a separate scene).
const HAND_LAYER := 1 << 19
const WORLD_LIGHT_MASK := 0xFFFFF & ~HAND_LAYER
const ENERGY_AMBIENT := 0.9
const ENERGY_DIR := 0.8
const LAMP_POOL := 4

var scene_id := "out"
var room: Variant = null
var campus: Dictionary = {}
var env: Environment
var sun_light: DirectionalLight3D
var cam_light: OmniLight3D
var room_lights: Array[OmniLight3D] = []
var room_base: Array[float] = []
var room_col: Array[Color] = []
var lamps: Array = []
var lamp_pool: Array[OmniLight3D] = []
var live_mats: Dictionary = {}     # name -> Array[BaseMaterial3D]
var time := 0.0
var reduce_flash := false
## VisualState.patrolFlick / patrolRed: the patroller's approach beat and its threat tint.
var patrol_flick := 0.0
## Lamp crackles since the last take (k, pan), heard from crackle_from (the camera).
var crackles: Array = []
## A revisit's broken lamp (index, modulo the room's lamps), −1 for none.
var dread_lamp := -1
static var shadows_on := false     # the quality setting (sun shadows from 精细 up)
## The picture quality (GameSettings 0–4) and whether the Mobile renderer runs (no SSAO / SSIL / volumetric fog).
static var quality := 2
static var mobile_renderer := false
## Per quality: screen-space ambient occlusion, glow on bright tubes and screens, how many of the nearest lamps cast
## shadows, volumetric fog. Presentation only: nothing here feeds a rule.
const Q_SSAO := [false, false, true, true, true]
const Q_GLOW := [false, true, true, true, true]
const Q_LAMP_SHADOWS := [0, 0, 1, 2, 4]
const Q_VOLUMETRIC := [false, false, false, false, true]
## Light contrast from 精细 up: part of the flat ambient (and the eye-level camera fill, which hides every shadow) moves
## into the lamps and the sun, so light pools, falloff and shadows read — the average brightness stays about the same.
const Q_LAMP_GAIN := [1.0, 1.0, 3.4, 3.6, 3.8]
const Q_INDOOR_AMB := [1.0, 1.0, 0.8, 0.78, 0.76]
const Q_CAM_GAIN := [1.0, 1.0, 0.75, 0.72, 0.7]
const Q_SUN_GAIN := [1.0, 1.0, 1.6, 1.7, 1.8]
const Q_OUTDOOR_AMB := [1.0, 1.0, 0.8, 0.76, 0.72]
## Daylight through the windows (indoors, by day): a soft directional sky light from the side the room's outer windows
## face, casting the window frames onto floor and desks. Energy at full day; the flat ambient gives a little back.
const Q_WINDOW := [0.0, 0.0, 3.0, 3.2, 3.4]
const WINDOW_AMBIENT_CUT := 0.12
const WINDOW_PITCH := 28.0
## In the normal-coloured world (opening, false-normal) the lamps already run at full power: cap the lamp gain there
## so the ceiling above a tube does not burn out.
const NORMAL_LAMP_GAIN := 1.5
## The old lamps sit a hand's width under the ceiling; with the stronger lamps that burns a white patch into it.
## From 精细 up the light itself hangs this much lower (the tube model does not move).
const LAMP_DROP := 0.45
## Tubes, screens and signs: emission pushed past the glow threshold.
const Q_EMIT_GAIN := [1.0, 1.6, 2.2, 2.4, 2.6]
var _shadow_pick := 0.0
## Daylight through each outer window: a spot just inside the pane, shaped by window_gobo().
var windows: Array = []
var window_lights: Array[SpotLight3D] = []
static var _gobo: ImageTexture
var brightness := 1.0              # the brightness setting (100 % = 1.0)
var world_normal := 0.0
var fake_normal := 0.0
var post_exposure := 1.0
var gaze := 0.0
var crowd_state: Dictionary = {}
var terms := {}  # lightState terms before physical-unit mapping and overcast
var lamp_dark: Dictionary = {}     # A2: corridor lamps whose tubes are dead (AtmosModule.dark_lamps)
var lamp_mul: Dictionary = {}      # lamp index → multiplier (the timed lamp scene)
var atmos_mods: Dictionary = {}    # A7: AtmosModule.light_mods, set each frame
var crackle_from: Node3D
var _flick_prev: Dictionary = {}
var _crackle_last := 0.0
var patrol_red := 0.0
## Anomaly effects on the light: the blackout, and the rains pressing the sky down (overcast eases 0.6 / s).
var blackout := false
var overcast_target := 0.0
var overcast := 0.0
var _lamp_pick := 0.0
var _stair_rise := 0.0
var _stair_levels := 0


func setup(id: String, room_data: Variant, model: Node, stair_rise: float) -> void:
	scene_id = id
	room = room_data
	campus = CampusData.campus()
	env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# ScenePost owns the original curve; applying ACES twice destroys dark detail.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# The old sky is only a gradient backdrop (makeSky); a flat colour avoids a radiance Sky per scene.
	env.background_mode = Environment.BG_COLOR
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
	sun_light = DirectionalLight3D.new()
	sun_light.light_cull_mask = WORLD_LIGHT_MASK
	sun_light.shadow_enabled = shadows_on
	sun_light.name = "SunMoon"
	add_child(sun_light)
	cam_light = OmniLight3D.new()
	cam_light.light_cull_mask = WORLD_LIGHT_MASK
	cam_light.name = "CameraFill"
	cam_light.omni_range = float(campus.get("light_cfg", {}).get("camDist", 6.5))
	cam_light.omni_attenuation = 1.8
	add_child(cam_light)
	if room != null:
		_add_room_lights(stair_rise)
		var tile := float(room.get("th", CampusGeometry.TTILE)) * CampusGeometry.U2M
		var half := float(room["rows"]) * tile * 0.5
		var lamp_rows: Array = []
		for l: OmniLight3D in room_lights:
			lamp_rows.append(floori((l.position.z + half) / tile))
		lamp_dark = AtmosModule.dark_lamps(room, lamp_rows)
	else:
		lamps = CampusData.layout("out").get("lamps", [])
		for i in LAMP_POOL:
			var l := OmniLight3D.new()
			l.name = "StreetLamp%d" % i
			l.light_cull_mask = WORLD_LIGHT_MASK
			l.omni_range = float(campus.get("light_cfg", {}).get("lampDist", 15))
			l.omni_attenuation = 2.0
			l.light_color = Color(1.0, 0.86, 0.62)
			l.light_energy = 0.0
			add_child(l)
			lamp_pool.append(l)
	if model != null:
		_collect_live(model)
	_rebuild_windows(model)
	apply_quality()


## Model tiers may use different panes. Drop stale lights when rebinding a model.
func _rebuild_windows(model: Node) -> void:
	for spot: SpotLight3D in window_lights:
		spot.free()
	window_lights.clear()
	windows.clear()
	if model != null and room != null and not _open_air():
		windows = find_windows(model, room as Dictionary)
	for w: Dictionary in windows:
		var spot := SpotLight3D.new()
		spot.name = "WindowLight%d" % window_lights.size()
		spot.light_cull_mask = WORLD_LIGHT_MASK
		spot.light_energy = 0.0
		spot.light_specular = 0.5
		spot.spot_range = 9.0
		spot.spot_angle = 46.0
		spot.spot_attenuation = 0.7
		spot.spot_angle_attenuation = 0.5
		spot.light_projector = window_gobo()
		# Only the windows around the player are lit; the engine fades the rest out with distance.
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = 16.0
		spot.distance_fade_length = 6.0
		spot.distance_fade_shadow = 12.0
		var inward: Vector3 = -(w["out"] as Vector3)
		var ray := (inward * cos(deg_to_rad(WINDOW_PITCH)) + Vector3.DOWN * sin(deg_to_rad(WINDOW_PITCH))).normalized()
		add_child(spot)
		spot.position = (w["at"] as Vector3) + inward * 0.12
		spot.look_at(spot.position + ray, Vector3.UP)
		spot.visible = false
		window_lights.append(spot)

## The room's outer windows, from the model: the panes are the surfaces with the live material "winSky" (the old
## build's sky seen through the glass). A pane triangle is an outer window when the floor plan has a walkable tile on
## exactly one side of it; neighbouring panes on the same wall are joined into one window. Returns
## [{"at": centre, "out": unit vector pointing outside, "w": width, "h": height}].
static func find_windows(model: Node, plan: Dictionary) -> Array:
	var grid: Array = plan.get("grid", [])
	if grid.is_empty():
		return []
	var tile := float(plan.get("tw", CampusGeometry.TTILE)) * CampusGeometry.U2M
	var half := Vector2(float(plan["cols"]), float(plan["rows"])) * tile * 0.5
	var open_at := func(x: float, z: float) -> bool:
		var c := floori((x + half.x) / tile)
		var r := floori((z + half.y) / tile)
		if r < 0 or r >= grid.size() or c < 0 or c >= String(grid[r]).length():
			return false
		return String(grid[r]).substr(c, 1) != "#"
	var panes := {}     # outward side -> Array of [along, wall coordinate, y low, y high, area]
	var nodes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	nodes.append_array(model.find_children("*", "MultiMeshInstance3D", true, false))
	for n: Node in nodes:
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		var places: Array[Transform3D] = [_to_model(gi, model)]
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			places.clear()
			for i in mm.instance_count:
				places.append(_to_model(gi, model) * mm.get_instance_transform(i))
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.resource_name != "wdfz_live:winSky":
				continue
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			var count := idx.size() if not idx.is_empty() else verts.size()
			for xf: Transform3D in places:
				for t in range(0, count - 2, 3):
					var a := xf * verts[idx[t] if not idx.is_empty() else t]
					var b := xf * verts[idx[t + 1] if not idx.is_empty() else t + 1]
					var c := xf * verts[idx[t + 2] if not idx.is_empty() else t + 2]
					var nrm := (b - a).cross(c - a)
					var area := nrm.length() * 0.5
					if area < 0.0001 or absf(nrm.y) > 0.3 * nrm.length():
						continue
					var mid := (a + b + c) / 3.0
					var axis := Vector3(1, 0, 0) if absf(nrm.x) > absf(nrm.z) else Vector3(0, 0, 1)
					var plus: bool = open_at.call(mid.x + axis.x * 0.9, mid.z + axis.z * 0.9)
					var minus: bool = open_at.call(mid.x - axis.x * 0.9, mid.z - axis.z * 0.9)
					if plus == minus:
						continue
					var out := -axis if plus else axis      # the side without floor is the outside
					if not panes.has(out):
						panes[out] = []
					var along := mid.z if axis.x != 0.0 else mid.x
					var wall := mid.x if axis.x != 0.0 else mid.z
					(panes[out] as Array).append([along, wall, minf(a.y, minf(b.y, c.y)), maxf(a.y, maxf(b.y, c.y)), area])
	var windows: Array = []
	for out: Vector3 in panes:
		var list: Array = panes[out]
		list.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
		var group: Array = []
		for i in list.size() + 1:
			if i < list.size() and (group.is_empty() or (float(list[i][0]) - float(group[-1][0]) < 0.7 and absf(float(list[i][1]) - float(group[-1][1])) < 0.5)):
				group.append(list[i])
				continue
			if not group.is_empty():
				var lo := float(group[0][0])
				var hi := float(group[-1][0])
				var y0 := INF
				var y1 := -INF
				var wall := 0.0
				var area := 0.0
				for g: Array in group:
					y0 = minf(y0, float(g[2]))
					y1 = maxf(y1, float(g[3]))
					wall += float(g[1]) * float(g[4])
					area += float(g[4])
				wall /= area
				if area > 0.4:
					var mid_along := (lo + hi) * 0.5
					var at := Vector3(wall, (y0 + y1) * 0.5, mid_along) if out.x != 0.0 else Vector3(mid_along, (y0 + y1) * 0.5, wall)
					windows.append({"at": at, "out": out, "w": maxf(0.6, hi - lo + 0.5), "h": y1 - y0})
			group = [list[i]] if i < list.size() else []
	return windows


## A window's shape for the light it throws: bright panes, dark frame and a mullion cross (2 × 2 panes).
static func window_gobo() -> ImageTexture:
	if _gobo != null:
		return _gobo
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := float(x) / float(n - 1)
			var v := float(y) / float(n - 1)
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var cross := minf(absf(u - 0.5), absf(v - 0.5))
			# The spot cone is round: keep the lit rectangle inside it, soft at the frame.
			var k := smoothstep(0.16, 0.22, edge) * smoothstep(0.012, 0.03, cross)
			img.set_pixel(x, y, Color(k, k, k))
	_gobo = ImageTexture.create_from_image(img)
	return _gobo


static func _to_model(node: Node3D, model: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != model:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


## Environment effects and shadow budget for the current quality (CampusLighting.quality).
func apply_quality() -> void:
	if env == null:
		return
	var q := clampi(quality, 0, 4)
	var full := not mobile_renderer
	env.ssao_enabled = full and Q_SSAO[q]
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.2 if q < 4 else 2.6
	env.ssao_power = 1.7
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.2       # occlusion also darkens lamp-lit corners, not only the ambient term
	env.ssao_ao_channel_affect = 0.0
	# Godot 4.6.3 Mobile can deadlock while compiling replay pipelines with glow
	# (e.g. the moth death on Vulkan Lavapipe). Keep this post effect on Forward+.
	env.glow_enabled = full and Q_GLOW[q]
	env.glow_intensity = 0.42
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for level in 7:
		env.set_glow_level(level, 1.0 if level in [1, 2, 3, 4] else 0.0)
	env.volumetric_fog_enabled = full and Q_VOLUMETRIC[q]
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.85, 0.88, 0.9)
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.0
	sun_light.shadow_enabled = shadows_on
	sun_light.shadow_blur = 1.5
	sun_light.directional_shadow_max_distance = 60.0 if q >= 3 else 40.0
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 3 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for spot: SpotLight3D in window_lights:
		spot.shadow_bias = 0.05
		spot.shadow_normal_bias = 1.0
		spot.shadow_blur = 1.6
		spot.light_volumetric_fog_energy = 1.2
	if _stair_rise <= 0.0:
		for l: OmniLight3D in room_lights:
			l.position.y = float(l.get_meta("rest_y", l.position.y)) - (LAMP_DROP if q >= 2 else 0.0)
	for l: OmniLight3D in room_lights + lamp_pool:
		l.light_specular = 0.5
		l.shadow_bias = 0.06
		l.shadow_normal_bias = 1.2
		l.shadow_blur = 1.4
		l.light_volumetric_fog_energy = 0.6
	for mats: Array in live_mats.values():
		for mat: BaseMaterial3D in mats:
			if mat.emission_enabled:
				mat.emission_energy_multiplier = float(Q_EMIT_GAIN[q])
	_pick_shadow_lamps(null)
	_pick_shadow_windows(null)


## The lamps nearest the camera cast shadows (Q_LAMP_SHADOWS); the rest stay shadowless.
func _pick_shadow_lamps(camera: Camera3D) -> void:
	var lights: Array[OmniLight3D] = room_lights + lamp_pool
	var n := int(Q_LAMP_SHADOWS[clampi(quality, 0, 4)])
	if n == 0 or camera == null:
		for l: OmniLight3D in lights:
			l.shadow_enabled = false
		return
	var at := camera.global_position
	var order := lights.duplicate()
	order.sort_custom(func(a: OmniLight3D, b: OmniLight3D) -> bool: return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	for i in order.size():
		(order[i] as OmniLight3D).shadow_enabled = i < n and (order[i] as OmniLight3D).light_energy > 0.0


## The nearest lit windows cast shadows too (as many as lamps do at this quality).
func _pick_shadow_windows(camera: Camera3D) -> void:
	var n := int(Q_LAMP_SHADOWS[clampi(quality, 0, 4)])
	if n == 0 or camera == null:
		for spot: SpotLight3D in window_lights:
			spot.shadow_enabled = false
		return
	var at := camera.global_position
	var order := window_lights.duplicate()
	order.sort_custom(func(a: SpotLight3D, b: SpotLight3D) -> bool: return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	for i in order.size():
		(order[i] as SpotLight3D).shadow_enabled = i < n and (order[i] as SpotLight3D).visible


func shadow_lamps() -> int:
	var count := 0
	for l: OmniLight3D in room_lights + lamp_pool:
		count += 1 if l.shadow_enabled else 0
	return count


func _open_air() -> bool:
	if room == null:
		return true
	return scene_id == "teach6" or bool(room.get("flags", {}).get("gallery", false))


static func _hex(h: String) -> Color:
	return Color.html(h)


static func smooth01(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## lighting.js sunAt: overcast day 06:00–18:36 with a short muted glow either side.
func sun_at(h: float) -> Dictionary:
	var sun: Dictionary = campus.get("sun", {"rise": 6.0, "set": 18.6})
	var rise := float(sun["rise"])
	var span := float(sun["set"]) - rise
	var e := sin(PI * (h - rise) / span)
	var day := smooth01(-0.10, 0.32, e)
	var gold := smooth01(-0.24, 0.0, e) * (1.0 - smooth01(0.06, 0.42, e)) * 0.55
	var t := clampf((h - rise) / span, 0.0, 1.0)
	var az := PI * t
	return {"e": e, "day": day, "gold": gold, "dir": Vector3(cos(az), 0.10 + maxf(0.0, e) * 1.2, 0.55 * sin(az))}


func sky_colors(h: float) -> Array[Color]:
	var s := sun_at(h)
	var out: Array[Color] = []
	for j in 4:
		var n := _hex(SKY_NIGHT[j])
		var d := _hex(SKY_DAY[j])
		var g := _hex(SKY_GOLD[j])
		var c := n.lerp(d, s["day"])
		c = c.lerp(g, float(s["gold"]) * 0.85)
		out.append(c)
	return out


## Per frame: hour of day from the game clock (tsec), stair height for stairwell lamps.
func update(dt: float, tsec: float, camera: Camera3D) -> void:
	time += dt
	overcast += (overcast_target - overcast) * minf(1.0, dt * 0.6)
	if _stair_rise > 0.0 and camera != null:
		# addRoomLights in a stairwell: the three lamps follow the storey the player is on.
		var floor_i := mini(_stair_levels - 2, int(floorf(maxf(0.0, camera.global_position.y - 1.65) / _stair_rise)))
		for l: OmniLight3D in room_lights:
			l.position.y = maxi(floor_i, 0) * _stair_rise + float(l.get_meta("base_y", l.position.y))
	var h := fposmod(tsec, 1440.0) / 60.0
	var sun := sun_at(h)
	var indoor := room != null and not _open_air()
	var day := float(sun["day"])
	day += (1.0-day)*.6*world_normal
	day += (maxf(day,.85)-day)*fake_normal
	var am: Dictionary = {} if scene_id == "portal_tunnel" or scene_id == "lift_dream" else atmos_mods
	var dusk := float(am.get("dusk", 0.0))
	var cold := float(am.get("cold", 1.0))
	var tint: Array = am.get("tint", [1.0, 1.0, 1.0])
	day = maxf(0.0, day * (1.0 - dusk))
	var amb: float
	var hemi: float
	var dirv: float
	var pt_k: float
	if indoor:
		var garage := scene_id == "garage1"
		amb = 0.025 if garage else 0.048 + 0.028 * day
		hemi = 0.015 if garage else 0.022 + 0.030 * day
		dirv = 0.015 if garage else 0.02 + 0.09 * day
		pt_k = 0.8 if garage else 0.30 + 0.34 * day
		if scene_id == "portal_tunnel":
			amb = 0.14
			hemi = 0.1
			dirv = 0.08
			pt_k = 0.9
		amb = lerpf(amb,.38,world_normal)
		hemi = lerpf(hemi,.28,world_normal)
		dirv = lerpf(dirv,.32,world_normal)
		pt_k = lerpf(pt_k,1.0,world_normal)
	else:
		amb = 0.075 + 0.12 * day
		hemi = 0.10 + 0.24 * day
		dirv = 0.11 + 0.27 * day if day > 0.02 else 0.11
		pt_k = 1.0
	if scene_id == "lift_dream":
		var cfg: Dictionary = CampusData.maze_data()["cfg"]
		amb = float(cfg["amb"])
		hemi = float(cfg["hemi"])
		dirv = 0.0
		pt_k = 1.0
	var sun_col := Color(0.86, 0.88, 0.90).lerp(Color(0.92, 0.66, 0.50), sun["gold"])
	terms={"day":day,"amb":amb,"hemi":hemi,"dir":dirv,"pt":pt_k}
	var crowd_here: bool = LiftCrowdFx.here(crowd_state,scene_id) and crowd_state.get("phase") != "gone"
	if crowd_here:
		pt_k *= LiftCrowdFx.light_mul(float(crowd_state.get("age",0)),reduce_flash)
	var gaze_mul := 1.0-.88*gaze
	var dc := Color(0.55, 0.66, 0.86).lerp(sun_col, smooth01(0.0, 0.35, day))
	var hs := Color(0.16, 0.21, 0.30).lerp(Color(0.70, 0.74, 0.78), day).lerp(Color(0.86, 0.62, 0.50), float(sun["gold"]) * 0.5)
	var hg := Color(0.05, 0.05, 0.06).lerp(Color(0.34, 0.34, 0.31), day)
	var ac := Color(0.36, 0.40, 0.50).lerp(Color(0.46, 0.48, 0.50), day)
	amb *= cold * (1.0 - 0.4 * dusk)
	hemi *= cold * (1.0 - 0.4 * dusk)
	ac = Color(ac.r * float(tint[0]), ac.g * float(tint[1]), ac.b * float(tint[2]))
	dc = Color(dc.r * float(tint[0]), dc.g * float(tint[1]), dc.b * float(tint[2]))
	if blackout and indoor:
		amb *= 0.16
		hemi *= 0.16
		dirv *= 0.12
		pt_k = 0.0
	amb *= 1.0 - 0.25 * overcast
	hemi *= 1.0 - 0.30 * overcast
	dirv *= 1.0 - 0.70 * overcast
	# Godot has no hemisphere light: fold it into the ambient term (sky and ground average).
	var ambient := ac * amb + (hs + hg) * 0.5 * hemi
	var strength := maxf(ambient.r, maxf(ambient.g, ambient.b))
	env.ambient_light_color = ambient / maxf(strength, 1e-4)
	var qi := clampi(quality, 0, 4)
	# Daylight through the windows: full by day, weaker under the rains, gone at night and in a blackout.
	var window_k := 0.0
	if indoor and not window_lights.is_empty() and float(Q_WINDOW[qi]) > 0.0 and not blackout:
		window_k = float(sun["day"]) * (1.0 - 0.6 * overcast) * (1.0 - dusk)
	var window_col := Color(0.78, 0.85, 0.93).lerp(Color(0.95, 0.74, 0.56), float(sun["gold"]))
	for spot: SpotLight3D in window_lights:
		spot.visible = window_k > 0.01
		spot.light_color = window_col
		spot.light_energy = float(Q_WINDOW[qi]) * window_k * gaze_mul
	var window_cut := 1.0 - WINDOW_AMBIENT_CUT * window_k
	var lamp_gain := lerpf(float(Q_LAMP_GAIN[qi]), minf(float(Q_LAMP_GAIN[qi]), NORMAL_LAMP_GAIN), maxf(world_normal, fake_normal))
	env.ambient_light_energy = strength * ENERGY_AMBIENT * gaze_mul * (float(Q_INDOOR_AMB[qi]) * window_cut if indoor else float(Q_OUTDOOR_AMB[qi]))
	sun_light.light_color = dc
	sun_light.light_energy = dirv * ENERGY_DIR * gaze_mul * (1.0 if indoor else float(Q_SUN_GAIN[qi]))
	var d: Vector3 = sun["dir"] if day > 0.02 and not indoor else MOON_DIR
	sun_light.look_at_from_position(d * 16.0, Vector3.ZERO, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.FORWARD)
	var sky := sky_colors(h)
	if not indoor:
		env.background_color = sky[1].lerp(sky[2], 0.5)
	if not indoor:
		var hz := sky[3] * 0.86
		var dens := 0.034 + (0.019 - 0.034) * day
		if room != null:
			dens *= 1.4
		if overcast > 0.0:
			dens += 0.030 * overcast
			hz = hz * (1.0 - 0.4 * overcast) + Color(0.09, 0.10, 0.12) * 0.4 * overcast
		env.fog_light_color = Color(hz.r, hz.g, hz.b)
		env.fog_density = dens
	else:
		var fnight := 1.0 - day
		var fc := Color(0.032 - 0.02 * fnight, 0.040 - 0.024 * fnight, 0.042 - 0.024 * fnight)
		var normal_fog := 0.0 if blackout else world_normal
		fc = fc.lerp(Color(.32,.35,.36),normal_fog)
		env.fog_light_color = fc
		env.background_color = fc
		env.fog_density = 0.09 if scene_id == "garage1" else (0.04 if scene_id == "portal_tunnel" else 0.072 + 0.03 * fnight)
		env.fog_density = lerpf(env.fog_density,.024,normal_fog)
	env.fog_density *= float(am.get("fog", 1.0))
	if scene_id == "lift_dream":
		var fog: Dictionary = CampusData.maze_data()["cfg"]["fog"]
		env.fog_light_color = Color(float(fog["r"]), float(fog["g"]), float(fog["b"]))
		env.background_color = env.fog_light_color
		env.fog_density = float(fog["density"])
	env.adjustment_enabled = false
	env.adjustment_brightness = 1.0
	# lighting.js dayExpo: outdoors the picture is pressed down to 0.6 at noon (DAY_K).
	post_exposure = 1.0 if indoor else 1.0 - .4*float(sun["day"])*(1.0-world_normal)
	env.tonemap_exposure = 1.0
	var sum := 0.0
	for i in room_lights.size():
		var flick := 0.94 if reduce_flash else room_flicker(i, time, day) * lamp_health(i)
		if scene_id == "lift_dream" or crowd_here:
			flick = 1.0
		# A revisit's broken lamp (fx/dread-fx.js lampMul): a glimmer, now and then a twitch.
		if dread_lamp >= 0 and i == dread_lamp % room_lights.size():
			flick *= 0.85 if not reduce_flash and (sin(time * 7.3 + 1.1) > 0.985 or sin(time * 2.9) > 0.996) else 0.06
		if lamp_dark.has(i):
			flick *= 0.35   # A2: a dead stretch of tubes, only the emergency signs' green
		flick *= float(lamp_mul.get(i, 1.0))
		if patrol_flick > 0.0:
			flick *= 1.0 - patrol_flick * (1.0 - patrol_beat(time))
		sum += flick
		# lightCrackle: a lamp dropping out (contact jump) crackles when it is within 9 m.
		var was: float = _flick_prev.get(i, -1.0)
		_flick_prev[i] = flick
		if was > 0.5 and flick < 0.3 and time - _crackle_last >= 0.05 and crackle_from != null:
			var to_l := room_lights[i].global_position - crackle_from.global_position
			var dl := Vector2(to_l.x, to_l.z).length()
			if dl <= 9.0:
				_crackle_last = time
				crackles.append({"k": 1.0 - dl / 9.0, "pan": clampf(crackle_from.global_basis.x.dot(to_l.normalized()) * 0.8, -1.0, 1.0)})
		room_lights[i].light_energy = room_base[i] * pt_k * maxf(0.05, flick) * (1.0 + 0.3 * patrol_red) * ENERGY_POINT * gaze_mul * lamp_gain
		var bc := room_col[i]
		var lr := bc.r * 0.86
		var lg := bc.g * 0.98
		var lb := bc.b * 0.84
		room_lights[i].light_color = Color(lr + (1.0 - lr) * patrol_red, lg * (1.0 - 0.92 * patrol_red), lb * (1.0 - 0.95 * patrol_red))
	var k := clampf(sum / room_lights.size(), 0.2, 1.0) if not room_lights.is_empty() else 1.0
	_set_live("emit", Color(k, k, k))
	var dk := 0.3 if reduce_flash else dying_tube(time)
	_set_live("emitDying", Color(dk, dk * 0.97, dk * 0.97))
	var lcfg: Dictionary = campus.get("light_cfg", {})
	if camera != null:
		cam_light.global_position = camera.global_position
	cam_light.light_energy = (float(lcfg.get("camI", 0.9)) + float(lcfg.get("camIk", 0.45)) * day) * ENERGY_POINT * 9.0 * (0.08 if blackout and indoor else 1.0) * gaze_mul * float(Q_CAM_GAIN[qi])
	_lamps(dt, 1.0 - day if not indoor else 0.0, camera, sky, day)
	_shadow_pick -= dt
	if _shadow_pick <= 0.0:
		_shadow_pick = 0.5
		_pick_shadow_lamps(camera)
		_pick_shadow_windows(camera)


# ---- room lamps (scene.js addRoomLights) ----

func _add_room_lights(stair_rise: float) -> void:
	var r: Dictionary = room
	var tile_m := CampusGeometry.TTILE * CampusGeometry.U2M
	var w := int(r["cols"]) * tile_m
	var hgt := int(r["rows"]) * tile_m
	var pti := float(campus.get("light_cfg", {}).get("ptI", 26))
	if r.get("flags", {}).get("stairwell", false):
		_stair_rise = stair_rise
		for s: Dictionary in campus.get("stair_layout", []):
			if s["id"] == scene_id:
				_stair_levels = (s["rooms"] as Array).size()
		for p: Array in [[1.8, 2.35, -1.18], [1.8, stair_rise / 2.0 + 2.35, 7.05], [1.8, stair_rise + 2.35, -1.18]]:
			_add_light(Vector3(p[0], p[1], p[2]), 0xc4d5bc, pti * 1.1, 10.0)
			room_lights[room_lights.size() - 1].set_meta("base_y", float(p[1]))
		return
	var host := String(r.get("host", ""))
	var floor := int(r.get("floor", 0)) if r.get("floor") != null else 0
	var teach := host == "teach" and floor >= 1 and floor <= 5
	var table: Dictionary = campus.get("room_lights", {})
	var spec: Array = table.get(scene_id, table.get("teach" if teach else host, table.get("default", [])))
	for v: Array in spec:
		var x := float(v[0])
		var z := float(v[2])
		var mode := String(v[6]) if v.size() > 6 else ""
		if mode == "room":
			x *= w
			z *= hgt
		elif mode == "tile":
			x = x * tile_m - w / 2.0
			z = z * tile_m - hgt / 2.0
		_add_light(Vector3(x, float(v[1]), z), int(v[3]), pti * float(v[4]), float(v[5]))
	if teach:
		_add_light(Vector3(0, 2.75, 18.5 * tile_m - hgt / 2.0), 0xf2dcc0, pti * 1.2, 18.0)
	if teach or (host == "lab" and floor >= 1 and floor <= 5):
		var lift_col := 20.5 if teach else 10.5
		_add_light(Vector3(lift_col * tile_m - w / 2.0, 2.65, (int(r["rows"]) - 1.5) * tile_m - hgt / 2.0), 0xe2eeec, pti * 0.65, 10.0)
	if host == "bell" and r.get("flags", {}).get("spiral", false):
		var sp: Dictionary = campus.get("spiral", {})
		_add_light(Vector3(sp["cx"], float(sp["topH"]) / 2.0, float(sp["cz"]) + 2.0), 0xd8b080, pti * 0.5, 9.0)
		_add_light(Vector3(sp["cx"], float(sp["topH"]) + 2.6, sp["cz"]), 0xc8d0d8, pti * 0.8, 10.0)


func _add_light(pos: Vector3, col: int, intensity: float, dist: float) -> void:
	var l := OmniLight3D.new()
	l.light_cull_mask = WORLD_LIGHT_MASK
	l.position = pos
	l.omni_range = dist
	l.omni_attenuation = 2.0
	var c := Color.hex((col << 8) | 0xff)
	l.light_color = c
	l.set_meta("rest_y", pos.y)
	add_child(l)
	room_lights.append(l)
	room_base.append(intensity)
	room_col.append(c)


# ---- flicker (lighting.js) ----

static func lhash(a: float, b: float) -> float:
	var x := sin(a * 127.1 + b * 311.7) * 43758.5453
	return x - floorf(x)


func room_flicker(i: int, tt: float, day: float) -> float:
	var ph := i * 2.7
	var f := 0.93 + 0.07 * sin(tt * 7.3 + ph) + 0.03 * sin(tt * 23.1 + ph * 1.7)
	var seg := floorf((tt + ph * 3.0) / 7.0)
	if lhash(seg, i) < 0.5:
		var at := lhash(seg, i + 17) * 5.5
		var length := 0.4 + lhash(seg, i + 31) * 0.7
		var u := (tt + ph * 3.0) - seg * 7.0 - at
		if u > 0.0 and u < length and sin(u * 90.0) <= 0.1:
			f *= 0.12
	if day < 0.3 and sin(tt * 0.37 + ph * 5.3) > 0.985:
		f *= 0.15
	return f


## lampHealth: about three in ten lamps are dead, a quarter half-lit; lamp 0 always works.
func lamp_health(i: int) -> float:
	var id := scene_id
	var r := lhash(i * 3.1, id.length() * 7.7 + (id.unicode_at(id.length() - 1) if not id.is_empty() else 0))
	if i == 0:
		return 1.0
	if r < 0.3 and reduce_flash:
		return 0.12
	if r < 0.3:
		return 0.06 + 0.9 * maxf(0.0, sin(time * 0.8 + i * 4.1) - 0.97) * 30.0
	if r < 0.55:
		return 0.45
	return 1.0


## Two short flickers and a long dark, like a heartbeat (patrolBeat).
func patrol_beat(tt: float) -> float:
	if reduce_flash:
		return 0.65 + 0.15 * sin(tt * 1.5)
	var u := fposmod(tt * 0.9, 1.0)
	return 0.1 if (u < 0.08 or (u > 0.16 and u < 0.24)) else (0.25 if (u > 0.5 and u < 0.7) else 1.0)


static func dying_tube(tt: float) -> float:
	var seg := floorf(tt / 2.3)
	var r := lhash(seg, 91)
	var u := tt - seg * 2.3
	if r < 0.45 and u < 0.5:
		return 0.95 if sin(u * 70.0 + r * 9.0) > 0.2 else 0.18
	if r > 0.9 and u < 1.6:
		return 0.75 + 0.2 * sin(u * 120.0)
	return 0.16 + 0.04 * sin(tt * 31.0)


# ---- street lamps and live materials (lampTick) ----

func _lamps(dt: float, night: float, camera: Camera3D, sky: Array[Color], day: float) -> void:
	var lamp_col := Color(0.36, 0.40, 0.42).lerp(Color(1.0, 0.86, 0.62), smooth01(0.15, 0.7, night))
	_set_live("lampHead", lamp_col)
	var sk := sky[2] * (0.55 + 0.45 * day)
	_set_live("winSky", sk)
	_set_live("winLit", Color(0.20, 0.27, 0.31).lerp(Color(0.95, 0.78, 0.48), smooth01(0.2, 0.8, night)))
	if lamp_pool.is_empty():
		return
	if night < 0.05 or lamps.is_empty() or camera == null:
		for l: OmniLight3D in lamp_pool:
			l.light_energy = 0.0
		return
	_lamp_pick -= dt
	if _lamp_pick <= 0.0:
		_lamp_pick = 0.35
		var c := camera.global_position
		var best := lamps.duplicate()
		best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return Vector2(float(a["x"]) - c.x, float(a["z"]) - c.z).length_squared() < Vector2(float(b["x"]) - c.x, float(b["z"]) - c.z).length_squared())
		for i in lamp_pool.size():
			if i < best.size():
				lamp_pool[i].position = Vector3(best[i]["x"], float(best[i]["y"]) - 0.25, best[i]["z"])
				lamp_pool[i].set_meta("on", true)
	var lamp_i := float(campus.get("light_cfg", {}).get("lampI", 15))
	for i in lamp_pool.size():
		var fl := 1.0
		if not reduce_flash and i == 1 and sin(time * 1.7) > 0.93:
			fl = 0.25 + 0.5 * absf(sin(time * 31.0))
		lamp_pool[i].light_energy = lamp_i * smooth01(0.15, 0.7, night) * fl * ENERGY_POINT * 2.0 * float(Q_LAMP_GAIN[clampi(quality, 0, 4)]) if lamp_pool[i].get_meta("on", false) else 0.0


func rebind_model(model: Node) -> void:
	live_mats.clear()
	if model != null:
		_collect_live(model)
	_rebuild_windows(model)
	apply_quality()


func _collect_live(model: Node) -> void:
	var meshes: Array[Mesh] = []
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			meshes.append((n as MeshInstance3D).mesh)
	for n: Node in model.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			meshes.append(mm.mesh)
	for mesh: Mesh in meshes:
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or not mat.resource_name.begins_with("wdfz_live:"):
				continue
			var key := mat.resource_name.substr(10)
			if not live_mats.has(key):
				live_mats[key] = []
			if not (live_mats[key] as Array).has(mat):
				live_mats[key].append(mat)


func _set_live(key: String, c: Color) -> void:
	for mat: BaseMaterial3D in live_mats.get(key, []):
		mat.albedo_color = c
		if mat.emission_enabled:
			mat.emission = c


func live_count() -> int:
	var n := 0
	for k: String in live_mats:
		n += (live_mats[k] as Array).size()
	return n
