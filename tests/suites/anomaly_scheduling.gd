extends "res://tests/support/test_suite.gd"
## Natural draws, changing locations and reachable windows; no forced anomaly IDs.


func _outside(at: Vector2, extra: Dictionary = {}) -> Dictionary:
	var ctx := _actx("out", at, {"day": 2, "need_where": "自由", "tsec": 900.0, "game_clock": 900.0})
	ctx.merge(extra, true)
	return ctx


func _new(seed_value: int, ctx: Dictionary) -> AnomalyModule:
	var a := CampusData.make_anomaly()
	a.reset()
	a.set_seed(seed_value)
	a.hist = ["chalk"] # A run after the normal opening blackboard event.
	a.set_context(ctx)
	return a


func test_location_draws() -> void:
	var outside := _outside(Vector2(750, 1100))
	var canteen := _actx("canteen1", CampusGeometry.tile_center(CampusData.layout("canteen1"), 10, 5), {"day": 2, "need_where": "自由"})
	var cold := 0
	var turn := 0
	for seed_value in 256:
		var a := _new(seed_value, outside)
		a._schedule_next()
		a.set_context(canteen)
		a.tick(float(a.an["next"]) + 0.01)
		cold += int(a.active_id() == "cold")
		turn += int(a.active_id() == "turn")
	check(cold >= 40 and turn < 100, "entering the canteen draws its local events instead of keeping an unannounced outdoor shoulder event (%d cold, %d turn / 256)" % [cold, turn])


func _window(building: String = "lab") -> Vector2:
	for o: Dictionary in CampusData.layout("out")["objects"]:
		if o["id"] == building:
			return Vector2(float(o["x"]) * 2 - 9, (float(o["y"]) + float(o["h"]) * 0.5) * 2)
	return Vector2.ZERO


func _natural_cup() -> AnomalyModule:
	for seed_value in 64:
		var a := _new(seed_value, _outside(_window()))
		for _frame in 601:
			a.tick(0.1)
			if a.is_active(): break
		if a.active_id() == "cup": return a
	return null


func test_cup_encounter() -> void:
	var a := _natural_cup()
	check(a != null, "a cup drawn next to a window starts a visible onsite warning without an extra invisible location check")
	if a == null: return
	check(float(a.an["data"]["wob"]) >= 8.0 and int(a.an["data"]["phase"]) == 0, "the onsite warning preserves the eight-second advance warning before the cup falls")
	var notices := a.take_events()
	check(notices.any(func(e: Dictionary) -> bool: return e.get("text", "") == AnomalyModule.DEFS["cup"]["msg"]), "the cup's sound/message and prop begin together")
	var origin := _window()
	var events: Array = []
	for frame in 115:
		# Walk away at the actual 21 old-world units/s; the cup must not chase us.
		a.set_context(_outside(origin + Vector2(-21.0 * minf(frame * 0.1, 4.0), 0)))
		a.tick(0.1)
		events.append_array(a.take_events())
	check(not _kinds(events).has("kill") and int(a.an["data"].get("phase", -1)) == 2, "walking away avoids a cup which still visibly falls, rather than cancelling it")
	check(Vector2(a.an["data"]["lx"], a.an["data"]["ly"]).distance_to(origin) < 0.001, "the long onsite warning fixes the landing beside the original window")
	check(a.cola_pending != null, "a visible cup encounter retains its night-time cola follow-up")
	# Save midway through the warning, through the same JSON boundary as real saves.
	var saved := _natural_cup()
	saved.tick(3.0)
	saved.take_events()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(saved.capture()))
	var loaded := CampusData.make_anomaly()
	check(loaded.validate(snapshot).is_empty(), "the onsite warning uses the existing save schema")
	loaded.restore(snapshot)
	var stay := _outside(origin)
	var original_events := _an_run(saved, stay, 9.0, "kill")
	var loaded_events := _an_run(loaded, stay, 9.0, "kill")
	check(_kinds(original_events).has("kill") and same_json(original_events, loaded_events), "staying beneath the cup is still lethal and saving cannot reroll its warning/landing")
	var indoors := _natural_cup()
	var inside := _actx("lab1", CampusGeometry.tile_center(CampusData.layout("lab1"), 10, 5))
	var enter_events := _an_run(indoors, inside, 0.1)
	check(not indoors.is_active() and not _kinds(enter_events).has("kill"), "entering the building during the warning remains a safe escape")
	# Once back outside at night, the real cup encounter produces its owed can.
	a.set_context(_outside(origin + Vector2(-84, 0), {"night": true, "tsec": 1400.0}))
	for _frame in 60: a.tick(0.1)
	check(a.active_id() == "cola" and a.cola_pending == null, "the scheduler naturally follows a survived cup with the owed night-time cola")


func test_boundaries() -> void:
	var rain := _new(16, _outside(Vector2(750, 1100)))
	rain.an["pre"] = "rain"
	rain.an["next"] = AnomalyModule.FORECAST_LEAD + 1.0
	check(rain.rain_cycle() < 0, "outdoor rain does not announce an entire scheduling interval early")
	rain.an["next"] -= 1.0
	var cycle := rain.rain_cycle()
	check(cycle >= 0 and rain.hear_rain(cycle, "guard1", false).is_empty(), "the forecast is audible outside and leaves indoor listeners eligible")
	check(rain.hear_rain(cycle, "out", false).contains("连廊"), "the first dry-land omen names reachable cover before exposure")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(rain.capture()))
	rain.restore(snapshot)
	check(rain.hear_rain(cycle, "out", true).is_empty(), "saving and reloading a forecast cannot repeat the cue")
	var late := _new(17, _outside(Vector2(750, 1100)))
	check(late.hear_rain(cycle, "out", true).contains("雨已经落下来了"), "a second student who comes out after the rain starts gets an immediate instruction")
	var nav := CampusData.patrol_nav()
	for building: String in ["teach", "lab", "admin"]:
		var at := _window(building)
		var a := _new(3, _outside(at))
		var cell := nav.cell("out", PatrolNav.point("out", at.x, at.y))
		check(nav.is_free("out", cell.x, cell.y) and a._when("cup"), "%s has a walkable exposed window within the cup radius" % building)
		var o := a._obj(building)
		a.set_context(_outside(Vector2((float(o["x"]) + float(o["w"]) / 2) * 2, (float(o["y"]) + float(o["h"])) * 2 + 9)))
		check(a.under_roof() and not a._when("cup"), "%s entrance canopy still excludes a new cup hazard" % building)
	var chase := _new(3, _outside(_window(), {"patrol_chase": true}))
	chase.tick(70.0)
	check(not chase.is_active() and float(chase.an["next"]) >= AnomalyModule.CHASE_GRACE, "nearby cups do not bypass chase grace")
	var quiet := _new(3, _outside(_window(), {"inspection_quiet": true}))
	quiet.tick(70.0)
	check(not quiet.is_active() and is_equal_approx(float(quiet.an["next"]), 60.0), "inspection quiet time still freezes the scheduler")
	# An explicitly promised forecast must retain its identity/time on both difficulties.
	for diff: String in ["easy", "hard"]:
		var forecast := _new(3, _outside(_window(), {"diff": diff}))
		forecast.an.merge({"pre": "cup", "locked": true, "next": 0.1}, true)
		forecast.tick(0.2)
		check(forecast.active_id() == "cup" and float(forecast.an["data"]["wob"]) < 1.0, "a promised %s cup keeps its original fall time, without adding another warning" % diff)
	var cooled := _natural_cup()
	if cooled != null:
		cooled.end_now()
		cooled.hist.append("turn") # Otherwise repeat suppression alone would exclude cup.
		var no_cup := true
		for _i in 64: no_cup = no_cup and cooled._pick() != "cup"
		check(no_cup, "the 150-game-minute cup cooldown remains in force")
		cooled.set_context(_outside(_window(), {"game_clock": 1050.0}))
		var cup_returns := false
		for _i in 64: cup_returns = cooled._pick() == "cup" or cup_returns
		check(cup_returns, "after 150 game minutes cup can be drawn again")


func test_reachability() -> void:
	var cases := [
		_actx("teach1", CampusGeometry.tile_center(CampusData.layout("teach1"), 40, 9), {"in_classroom": true}),
		_actx("teach1", CampusGeometry.tile_center(CampusData.layout("teach1"), 30, 17), {"night": true}),
		_actx("teach1", CampusGeometry.tile_center(CampusData.layout("teach1"), 60, 18), {"tile": "B"}),
		_actx("lab2", CampusGeometry.tile_center(CampusData.layout("lab2"), 20, 10)),
		_actx("canteen1", CampusGeometry.tile_center(CampusData.layout("canteen1"), 10, 5), {"tsec": 750.0}),
		_actx("teach6", CampusGeometry.tile_center(CampusData.layout("teach6"), 20, 10)),
		_outside(_window()),
		_outside(Vector2(1150, 776)),
		_outside(Vector2(1300, 2100), {"on_field": true}),
		_outside(Vector2(1610, 2100)),
	]
	var reached := {}
	for ctx: Dictionary in cases:
		ctx.merge({"day": 2, "need_where": "自由"}, true)
		for seed_value in 128:
			var a := _new(seed_value, ctx)
			a.hist = ["turn"] if ctx["scene"] != "out" else ["chalk"]
			a.an["rained"] = true
			a.tick(60.01)
			if not a.is_active(): a.tick(8.01)
			if a.is_active(): reached[a.active_id()] = true
	for id: String in AnomalyModule.IDS:
		if id == "cola": continue # The natural debt chain is tested above.
		check(reached.has(id), "%s remains naturally reachable at its appropriate place/time" % id)


func test_warning_view() -> void:
	var a := _natural_cup()
	if a == null:
		check(false, "natural cup warning is available to its presentation adapter")
		return
	var props := FallingProps.new()
	root.add_child(props)
	var at := CampusGeometry.to_scene(null, _window())
	var feet := Vector3(at.x, 0, at.y)
	props.build("cup", a.an["data"], null, feet, 0.0, 2)
	a.tick(3.0)
	var before := a.capture()
	props.advance(3.0, float(a.an["t"]), a.an["data"], null, feet)
	await _frames(2)
	check(props.body.is_visible_in_tree() and props.body.position.y > 10.0 and props.body.rotation.length() > 0.01,
		"three seconds into the natural warning the actual cup model is visible and wobbling on the sill")
	check(same_json(before, a.capture()), "drawing the onsite warning does not consume scheduler state")
	a.set_context(_outside(_window() + Vector2(-84, 0)))
	a.tick(6.0)
	props.advance(6.0, float(a.an["t"]), a.an["data"], null, feet + Vector3.LEFT * 9)
	await _frames(2)
	check(props.ring.visible and Vector2(props.ring.position.x, props.ring.position.z).distance_to(at) < 0.001,
		"the actual fall warning ring stays at the original window after the player walks away")
	props.free()
