class_name CooperativePatrol
extends RefCounted
## One simulation, personal eligibility/evidence. All candidates must be actually observed.
var main: PatrolModule
var target := ""
var permanent: Dictionary = {}
var regions: Dictionary = {}
var reports: Array = []
var lockers: Dictionary = {}


func synchronize(actors: Dictionary) -> void:
	for a: CooperativeActor in actors.values():
		a.watcher().pat = main.pat.duplicate(true)
		a.watcher().pat["permanent"] = permanent.has(a.id)
		a.watcher().pat["lockerMemory"] = lockers.get(a.id, {}).duplicate(true)
		if a.id != target:
			a.watcher().pat["locked"] = false
			a.watcher().pat["lock"] = 0.0
			a.watcher().pat["wirelessSignal"] = null
			a.watcher().pat["lastSeen"] = null
			a.watcher().pat["search"] = 0.0
		a.watcher().flick = main.flick
		a.watcher().red = main.red


func report(a: CooperativeActor) -> void:
	var watcher := a.watcher()
	watcher.reveal_wireless()
	var signal_data: Dictionary = watcher.pat["wirelessSignal"].duplicate(true)
	reports.append({"member": a.id, "signal": signal_data})
	while reports.size() > 16: reports.pop_front()


func sense(a: CooperativeActor, observation: Dictionary) -> void:
	if observation.is_empty(): return
	for pending: Dictionary in reports:
		if pending["member"] == a.id and pending["signal"].get("kind", "") == observation["kind"]:
			pending["signal"] = observation
			return
	reports.append({"member": a.id, "signal": observation})
	while reports.size() > 16: reports.pop_front()


func _take_report(alive: Array, contexts: Dictionary, precise_only: bool) -> Dictionary:
	# Preserve precise network pings, then use nearby sounds or coarser SAN reports.
	for kind: String in ([""] if precise_only else ["", "sprint", "san"]):
		for i in reports.size():
			var entry: Dictionary = reports[i]
			var signal_data: Dictionary = entry["signal"]
			if not entry["member"] in alive or signal_data.get("kind", "") != kind: continue
			if kind != "" and bool(contexts[entry["member"]].get("night", false)) and signal_data["point"]["scene"] != "out": continue
			return reports.pop_at(i)
	return {}


func step(dt: float, actors: Dictionary, contexts: Dictionary) -> Array:
	var alive: Array = []
	for i in range(reports.size() - 1, -1, -1):
		var queued: Dictionary = reports[i]["signal"]
		if not queued.has("kind"): continue
		queued["remaining"] = float(queued["remaining"]) - dt
		if queued["remaining"] <= 0.0: reports.remove_at(i)
	synchronize(actors)
	for id: String in actors:
		if not contexts.has(id): continue
		var a: CooperativeActor = actors[id]
		a.watcher().set_context(contexts[id])
		var region: Variant = a.watcher().region()
		if region != regions.get(id):
			regions[id] = region
			if region != null:
				main.set_context(contexts[id])
				main._enqueue(String(region))
				for e: Dictionary in main.take_events(): a.event("notice", e)
		if not a.fate().over():
			alive.append(id)
			var noise := a.watcher().sprint_report()
			if id == target and main.pat["sense"] != null:
				main.use_sense(noise)
			else:
				sense(a, noise)
	alive.sort()
	var responsible := permanent.has(target) or main.pat["wirelessSignal"] != null
	var allowed: bool = target in alive and (responsible or (actors[target].watcher().eligible() and not actors[target].watcher().exempt()))
	var maintaining: bool = allowed and (bool(main.pat["locked"]) or float(main.pat["lock"]) > 0.0 or float(main.pat["search"]) > 0.0 or responsible)
	if not maintaining:
		var next := ""
		var next_signal: Variant = null
		var best := INF
		for id: String in alive:
			var a: CooperativeActor = actors[id]
			var w := a.watcher()
			var known: bool = permanent.has(id) or (w.eligible() and not w.exempt() and (w.sees() or bool(w.hide["seen"])))
			if not known: continue
			var rank := w.distance() - a.school().viol * 0.1 - (100000.0 if permanent.has(id) else 0.0)
			if rank < best:
				best = rank
				next = id
		if next.is_empty():
			var active_sense: bool = target in alive and main.pat["sense"] != null
			var report_data := _take_report(alive, contexts, active_sense)
			if not report_data.is_empty():
				next = String(report_data["member"])
				next_signal = report_data["signal"]
			elif active_sense:
				next = target
		if next != target:
			main.clear_chase()
			main.pat["sense"] = null
			target = next
		main.pat["wirelessSignal"] = null
		if next_signal != null:
			if next_signal.has("kind"): main.use_sense(next_signal)
			else: main.pat["wirelessSignal"] = next_signal
	var context := {"scene": "", "x": 0.0, "y": 0.0, "dead": false, "playing": true, "viol": 0.0}
	if contexts.has(target):
		context = contexts[target]
		main.hide = actors[target].watcher().hide
		main.camouflage = actors[target].watcher().camouflage
	else:
		main.hide = {"on": false, "c": 0, "r": 0, "seen": false, "t": 0.0, "near": false}
		main.camouflage = Callable()
	main.pat["permanent"] = permanent.has(target)
	main.pat["lockerMemory"] = lockers.get(target, {}).duplicate(true)
	main.set_context(context)
	main.tick(dt)
	if target != "": lockers[target] = main.pat["lockerMemory"].duplicate(true)
	var events := main.take_events()
	synchronize(actors)
	var out: Array = []
	for e: Dictionary in events:
		e["member"] = target
		out.append(e)
	return out


func capture() -> Dictionary:
	return {"patrol": main.capture(), "target": target, "permanent": permanent.duplicate(true), "regions": regions.duplicate(true), "reports": reports.duplicate(true), "lockers": lockers.duplicate(true)}


func restore(data: Dictionary) -> void:
	main.restore(data["patrol"])
	target = String(data["target"])
	permanent = data["permanent"].duplicate(true)
	regions = data["regions"].duplicate(true)
	reports = data["reports"].duplicate(true)
	lockers = data["lockers"].duplicate(true)
