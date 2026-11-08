class_name MazeGeometry
extends RefCounted
## Exact scene-metre geometry from modules/void-maze/maze.js. One voxel field feeds
## rule queries and the physics adapter; visual meshes alone never define walkable space.

var cfg: Dictionary
var walks: Array
var _voxels := PackedByteArray()
var _nx: int
var _ny: int
var _nz: int
var _origin: Vector3
var _boxes: Array[AABB] = []


func _init(data: Dictionary) -> void:
	cfg = data["cfg"].duplicate(true)
	walks = data["walk"].duplicate(true)
	_nx = int(cfg["cols"])
	_ny = int(cfg["ny"])
	_nz = int(cfg["rows"])
	_origin = Vector3(float(cfg["x0"]), float(cfg["y0"]), float(cfg["z0"]))
	_voxels.resize(_nx * _ny * _nz)
	_voxels.fill(1)
	for volume: Dictionary in data["air"]:
		_fill(volume["b"], 0)
	for volume: Dictionary in data["solid"]:
		_fill(volume["b"], 1)


func _index(x: int, y: int, z: int) -> int:
	return (y * _nz + z) * _nx + x


func _fill(b: Array, value: int) -> void:
	for y in range(maxi(0, int(b[2]) - int(_origin.y)), mini(_ny, int(b[3]) - int(_origin.y))):
		for z in range(maxi(0, int(b[4]) - int(_origin.z)), mini(_nz, int(b[5]) - int(_origin.z))):
			for x in range(maxi(0, int(b[0]) - int(_origin.x)), mini(_nx, int(b[1]) - int(_origin.x))):
				_voxels[_index(x, y, z)] = value


func cell(x: int, y: int, z: int) -> int:
	if y < 0:
		return 0
	if x < 0 or z < 0 or x >= _nx or z >= _nz or y >= _ny:
		return 1
	return _voxels[_index(x, y, z)]


static func surface_height(p: Dictionary, x: float, z: float) -> float:
	if x < float(p["x0"]) - 0.000001 or x > float(p["x1"]) + 0.000001 or z < float(p["z0"]) - 0.000001 or z > float(p["z1"]) + 0.000001:
		return -INF
	if p["t"] == "plat":
		return float(p["h"])
	var a := x if p["ax"] == "x" else z
	var k := clampf((a - float(p["a0"])) / (float(p["a1"]) - float(p["a0"])), 0.0, 1.0)
	return lerpf(float(p["h0"]), float(p["h1"]), k)


func ground_at(x: float, z: float, max_y: float) -> float:
	var best := -INF
	var ix := floori(x - _origin.x)
	var iz := floori(z - _origin.z)
	if ix >= 0 and iz >= 0 and ix < _nx and iz < _nz:
		for iy in range(mini(_ny - 1, floori(max_y - _origin.y - 1.0 + 1e-9)), -1, -1):
			if _voxels[_index(ix, iy, iz)] == 1:
				best = _origin.y + iy + 1.0
				break
	for p: Dictionary in walks:
		var h := surface_height(p, x, z)
		if h <= max_y + 1e-9 and h > best:
			best = h
	return best


static func _rect_depth(x: float, z: float, r: float, x0: float, z0: float, x1: float, z1: float) -> float:
	var dx := maxf(maxf(x0 - x, 0.0), x - x1)
	var dz := maxf(maxf(z0 - z, 0.0), z - z1)
	if dx == 0.0 and dz == 0.0:
		return r + minf(minf(x - x0, x1 - x), minf(z - z0, z1 - z))
	return maxf(0.0, r - sqrt(dx * dx + dz * dz))


func depth_at(x: float, z: float, radius: float, feet_y: float) -> float:
	var lo := feet_y + float(cfg["step"])
	var hi := feet_y + float(cfg["head"])
	var total := 0.0
	for iy in range(floori(lo - _origin.y), floori(hi - _origin.y - 1e-9) + 1):
		for iz in range(floori(z - radius - _origin.z), floori(z + radius - _origin.z) + 1):
			for ix in range(floori(x - radius - _origin.x), floori(x + radius - _origin.x) + 1):
				if cell(ix, iy, iz) == 0:
					continue
				var x0 := _origin.x + ix
				var z0 := _origin.z + iz
				if radius > 0.0:
					total += _rect_depth(x, z, radius, x0, z0, x0 + 1.0, z0 + 1.0)
				elif x >= x0 and x < x0 + 1.0 and z >= z0 and z < z0 + 1.0:
					total += 1.0
	for p: Dictionary in walks:
		var x0 := float(p["x0"])
		var x1 := float(p["x1"])
		var z0 := float(p["z0"])
		var z1 := float(p["z1"])
		if x + radius < x0 or x - radius > x1 or z + radius < z0 or z - radius > z1:
			continue
		var top := surface_height(p, clampf(x, x0, x1), clampf(z, z0, z1))
		if top <= lo or top - 0.3 >= hi:
			continue
		if radius > 0.0:
			total += _rect_depth(x, z, radius, x0, z0, x1, z1)
		elif x >= x0 and x <= x1 and z >= z0 and z <= z1:
			total += 1.0
	return total


## Greedy disjoint boxes cover exactly the occupied voxels. This avoids thousands of
## overlapping collision shapes, preserves voids and shares one field with ground_at/depth_at.
func solid_boxes() -> Array[AABB]:
	if not _boxes.is_empty():
		return _boxes
	var remaining := _voxels.duplicate()
	for y in _ny:
		for z in _nz:
			for x in _nx:
				if remaining[_index(x, y, z)] == 0:
					continue
				var x1 := x + 1
				while x1 < _nx and remaining[_index(x1, y, z)] == 1:
					x1 += 1
				var z1 := z + 1
				while z1 < _nz and _filled(remaining, x, x1, y, y + 1, z1, z1 + 1):
					z1 += 1
				var y1 := y + 1
				while y1 < _ny and _filled(remaining, x, x1, y1, y1 + 1, z, z1):
					y1 += 1
				for yy in range(y, y1):
					for zz in range(z, z1):
						for xx in range(x, x1):
							remaining[_index(xx, yy, zz)] = 0
				_boxes.append(AABB(_origin + Vector3(x, y, z), Vector3(x1 - x, y1 - y, z1 - z)))
	return _boxes


func _filled(values: PackedByteArray, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> bool:
	for y in range(y0, y1):
		for z in range(z0, z1):
			for x in range(x0, x1):
				if values[_index(x, y, z)] == 0:
					return false
	return true


func spawn(rng: RandomNumberGenerator) -> Dictionary:
	var area: Dictionary = cfg["spawn"]
	var x := 0.0
	var z := 0.0
	var h := float(area["h"])
	for attempt in 40:
		x = rng.randf_range(float(area["x0"]), float(area["x1"]))
		z = rng.randf_range(float(area["z0"]), float(area["z1"]))
		if absf(ground_at(x, z, h + float(cfg["step"])) - h) < 0.000001 and depth_at(x, z, 1.0 / 3.0 + 0.05, h) == 0.0:
			break
	var ang := floorf(rng.randf() * 4.0) * PI * 0.5 + PI * 0.25
	return {"position": [x, h + 0.01, z], "yaw": CampusGeometry.yaw_from_ang(ang), "pitch": 0.0}


func valid_ground_pose(pose: Dictionary) -> bool:
	var p: Array = pose["position"]
	var h := ground_at(float(p[0]), float(p[2]), float(p[1]) + float(cfg["step"]))
	return is_finite(h) and absf(h - float(p[1])) <= float(cfg["snap"]) and depth_at(float(p[0]), float(p[2]), 1.0 / 3.0, h) == 0.0
