class_name MazePatrolNav
extends RefCounted
## navigation.js maze: half-metre A* nodes include foot height, with a tested midpoint
## on every edge. Uses the same voxels and ramps as player collision, never a flat proxy.
const DIRS := [Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const MAX_VISITS := 100000
var shape: MazeGeometry
var room: Dictionary
var _links: Dictionary = {}
var _paths: Dictionary = {}
var _warm_queue: Array = [{"x":0.0,"z":0.0,"h":0.0}]
var _warm_seen: Dictionary = {Vector3i.ZERO:true}
var _warm_at := 0
var warm_done := false


func _init(geometry: MazeGeometry, layout: Dictionary) -> void:
	shape=geometry
	room=layout


func _node(p: Dictionary) -> Dictionary:
	# JavaScript Math.round rounds negative ties toward +infinity.
	return {"x":floorf((float(p["x"])-float(room["cx"]))*CampusGeometry.U2M*2+.5)/2,
		"z":floorf((float(p["y"])-float(room["cy"]))*CampusGeometry.U2M*2+.5)/2,"h":float(p.get("fy",0))}


static func _key(p: Dictionary) -> Vector3i:
	return Vector3i(roundi(p["x"]*2),floori(p["h"]*1000+.5),roundi(p["z"]*2))


func point(x: float, z: float, h: float = 0) -> Dictionary:
	return PatrolNav.point("lift_dream",float(room["cx"])+x/CampusGeometry.U2M,float(room["cy"])+z/CampusGeometry.U2M,h)


static func _distance(a: Dictionary, b: Dictionary) -> float:
	var x: float=a["x"]-b["x"]
	var z: float=a["z"]-b["z"]
	var h: float=a["h"]-b["h"]
	return sqrt(x*x+z*z+h*h)


static func _push(heap: Array, v: Dictionary) -> void:
	heap.append(v)
	var i:=heap.size()-1
	while i>0:
		var parent: int=(i-1)>>1
		if heap[parent]["f"]<=v["f"]: break
		heap[i]=heap[parent]
		i=parent
	heap[i]=v


static func _pop(heap: Array) -> Dictionary:
	var first: Dictionary=heap[0]
	var v: Dictionary=heap.pop_back()
	if not heap.is_empty():
		var i:=0
		while i*2+1<heap.size():
			var child:=i*2+1
			if child+1<heap.size() and heap[child+1]["f"]<heap[child]["f"]: child+=1
			if heap[child]["f"]>=v["f"]: break
			heap[i]=heap[child]
			i=child
		heap[i]=v
	return first


func _neighbors(p: Dictionary) -> Array:
	# Static geometry: caching tested edges avoids repeating voxel queries every chase frame.
	var key:=str(_key(p))+":"+str(p["h"])
	if _links.has(key): return _links[key]
	var out: Array=[]
	for d: Vector2i in DIRS:
		var x: float=p["x"]+d.x*.5
		var z: float=p["z"]+d.y*.5
		var g:=shape.ground_at(x,z,p["h"]+shape.cfg["step"])
		if not is_finite(g) or g<p["h"]-shape.cfg["snap"] or shape.depth_at(x,z,.30,g)>1e-7: continue
		var mx: float=(x+p["x"])/2
		var mz: float=(z+p["z"])/2
		var mh:=shape.ground_at(mx,mz,maxf(p["h"],g)+shape.cfg["step"])
		if not is_finite(mh) or absf(mh-(p["h"]+g)/2)>.45 or shape.depth_at(mx,mz,.30,mh)>1e-7: continue
		out.append({"x":x,"z":z,"h":g})
	_links[key]=out
	return out


func warm_step(milliseconds: float = 2.0) -> void:
	# Cache only static edges, without touching any simulation state. The app spreads
	# this over ordinary frames long before a patrol needs its first deep maze route.
	if warm_done or milliseconds<=0: return
	var end:=Time.get_ticks_usec()+int(minf(4,milliseconds)*1000)
	while _warm_at<_warm_queue.size() and Time.get_ticks_usec()<end:
		var p: Dictionary=_warm_queue[_warm_at]
		_warm_at+=1
		for q: Dictionary in _neighbors(p):
			var key:=_key(q)
			if not _warm_seen.has(key):
				_warm_seen[key]=true
				_warm_queue.append(q)
	if _warm_at>=_warm_queue.size():
		warm_done=true
		_warm_queue.clear()
		_warm_seen.clear()


func path(a: Dictionary, b: Dictionary) -> Array:
	var start:=_node(a)
	var goal:=_node(b)
	var cache_key:=str(start)+">"+str(goal)
	if _paths.has(cache_key): return _paths[cache_key].duplicate()
	var sk:=_key(start)
	var seen: Dictionary={sk:0.0}
	var previous: Dictionary={}
	var nodes: Dictionary={sk:start}
	var heap: Array=[]
	_push(heap,{"k":sk,"cost":0.0,"f":_distance(start,goal)})
	var end: Variant=null
	for count in MAX_VISITS:
		if heap.is_empty(): break
		var cur:=_pop(heap)
		var p: Dictionary=nodes[cur["k"]]
		if cur["cost"]>seen[cur["k"]]+1e-8: continue
		if _distance(p,goal)<.65:
			end=cur["k"]
			break
		for q: Dictionary in _neighbors(p):
			var k:=_key(q)
			var cost: float=cur["cost"]+_distance(p,q)
			if not seen.has(k) or cost<seen[k]-1e-8:
				seen[k]=cost
				nodes[k]=q
				previous[k]=cur["k"]
				_push(heap,{"k":k,"cost":cost,"f":cost+_distance(q,goal)})
	var out: Array=[]
	while end!=null:
		var p: Dictionary=nodes[end]
		out.append(point(p["x"],p["z"],p["h"]))
		end=previous.get(end)
	out.reverse()
	if _paths.size()>=128: _paths.erase(_paths.keys()[0])
	_paths[cache_key]=out
	return out.duplicate()


func supported(p: Dictionary) -> bool:
	var x: float=(float(p["x"])-float(room["cx"]))*CampusGeometry.U2M
	var z: float=(float(p["y"])-float(room["cy"]))*CampusGeometry.U2M
	var h:=float(p.get("fy",0))
	var ground:=shape.ground_at(x,z,h+.45)
	return is_finite(ground) and absf(ground-h)<=.45 and shape.depth_at(x,z,.30,h)<=1e-7


func occluded(x: float, y: float, h: float) -> bool:
	return shape.depth_at((x-float(room["cx"]))*CampusGeometry.U2M,(y-float(room["cy"]))*CampusGeometry.U2M,0,h)>0
