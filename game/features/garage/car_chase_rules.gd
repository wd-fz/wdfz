class_name CarChaseRules
extends RefCounted
## Driving physics and the win/fail rules (domain/car-chase.js, reference wd-fz.github.io@0bf508a).
## Input / state / config in, result out; nothing here knows about the view, sound or the session.

const DISTANCE := 320.0
const MAX_SPEED := 22.0
const ACCEL := 9.0
const BRAKE := 15.0
const DRAG := 2.0
const STEER := 4.2
const EDGE := 3.2
const PURSUIT_LIMIT := 80.0
## [distance, lateral position]
const OBSTACLES := [[45.0, 0.0], [78.0, 2.7], [108.0, -2.7], [190.0, 0.0], [225.0, 2.7], [290.0, 0.0]]
## [distance, the side you must be on (+1 right, -1 left)]
const FORKS := [[150.0, 1], [255.0, -1]]


static func new_state() -> Dictionary:
	return {"distance": 0.0, "x": 0.0, "speed": 0.0, "hp": 3, "pursuit": 0.0, "nextObstacle": 0, "nextFork": 0}


## State after a failure: back to a checkpoint with full health.
static func reset_to(d: Dictionary, checkpoint: float) -> void:
	d["distance"] = checkpoint
	d["speed"] = 0.0
	d["hp"] = 3
	d["pursuit"] = 0.0
	d["nextObstacle"] = OBSTACLES.filter(func(o: Array) -> bool: return float(o[0]) <= checkpoint).size()
	d["nextFork"] = FORKS.filter(func(f: Array) -> bool: return float(f[0]) <= checkpoint).size()


## input: {throttle, braking, steering}. Returns {events, failure?: {message, checkpoint}, won?}.
static func step(d: Dictionary, input: Dictionary, dt: float) -> Dictionary:
	var events: Array = []
	var throttle := bool(input.get("throttle", false))
	var braking := bool(input.get("braking", false))
	var steering := float(input.get("steering", 0.0))
	d["speed"] = clampf(float(d["speed"]) + (ACCEL if throttle else -DRAG) * dt - (BRAKE * dt if braking else 0.0), 0.0, MAX_SPEED)
	d["x"] = clampf(float(d["x"]) + clampf(steering, -1.0, 1.0) * STEER * dt, -EDGE, EDGE)
	d["pursuit"] = clampf(float(d["pursuit"]) + (3.0 if float(d["speed"]) < 7.0 else -2.5) * dt, 0.0, PURSUIT_LIMIT)
	d["distance"] = float(d["distance"]) + float(d["speed"]) * dt
	if float(d["pursuit"]) >= PURSUIT_LIMIT:
		return {"events": events, "failure": {"message": "黑影追上了车。后窗上全是贴上来的手。", "checkpoint": maxf(0.0, float(d["distance"]) - 30.0)}}
	while int(d["nextObstacle"]) < OBSTACLES.size() and float(d["distance"]) >= float(OBSTACLES[int(d["nextObstacle"])][0]):
		var o: Array = OBSTACLES[int(d["nextObstacle"])]
		d["nextObstacle"] = int(d["nextObstacle"]) + 1
		if absf(float(d["x"]) - float(o[1])) < 1.25:
			d["hp"] = int(d["hp"]) - 1
			d["speed"] = float(d["speed"]) * 0.55
			events.append({"type": "hit"})
			if int(d["hp"]) <= 0:
				return {"events": events, "failure": {"message": "车撞在路障上，黑影从破碎的窗户里伸进手。", "checkpoint": maxf(0.0, float(o[0]) - 25.0)}}
	while int(d["nextFork"]) < FORKS.size() and float(d["distance"]) >= float(FORKS[int(d["nextFork"])][0]):
		var fork: Array = FORKS[int(d["nextFork"])]
		if float(d["x"]) * float(fork[1]) < 1.0:
			return {"events": events, "failure": {"message": "路牌在后视镜里倒了过来。前面的路又通回学校。", "checkpoint": float(fork[0]) - 30.0}}
		d["nextFork"] = int(d["nextFork"]) + 1
		events.append({"type": "fork"})
	if float(d["distance"]) >= DISTANCE and int(d["nextFork"]) == FORKS.size():
		return {"events": events, "won": true}
	return {"events": events}
