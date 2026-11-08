class_name PlaneGame
extends RefCounted
## The paper-plane game of the phone (phone.js, reference wd-fz.github.io@0bf508a): a plane flaps
## between shelves, one point a shelf passed. When a round ends with a score and the phone is not hot,
## SAN comes back (up to 6 points of rest, scaled by the pressure) and the phone is hot for 45 s.
## Pure rules; the panel draws them. Not saved (a run starts with a cool phone).

const W := 200.0
const H := 340.0
const GAP := 112.0
const SPEED := 92.0
const GRAVITY := 620.0
const FLAP := -215.0
const COOL := 45.0
const MAX_GAIN := 6.0

var st := "ready"      # ready | fly | over
var y := H * 0.45
var vy := 0.0
var pipes: Array = []  # {x, gy, pass}
var score := 0
var t := 0.0
var cool := 0.0
var gain := 0.0
var msg := ""


func reset() -> void:
	st = "ready"
	y = H * 0.45
	vy = 0.0
	pipes = []
	score = 0
	t = 0.0
	msg = ""


func full_reset() -> void:
	reset()
	cool = 0.0
	gain = 0.0


## A tap or the space bar. Returns true when it started or restarted a round.
func flap() -> bool:
	if st == "over":
		reset()
		return true
	var started := st == "ready"
	if started:
		st = "fly"
	vy = FLAP
	return started


## Advance a frame. Returns events: [{"kind": "end", "gain": float}] when the round ended.
## rest_mul: the campus pressure's rest factor; rnd: a presentation random in [0, 1).
func tick(dt: float, rest_mul: float, rnd: Callable) -> Array:
	var out: Array = []
	if cool > 0.0:
		cool = maxf(0.0, cool - dt)
	if st != "fly":
		return out
	vy += GRAVITY * dt
	y += vy * dt
	t += dt
	if pipes.is_empty() or float(pipes[pipes.size() - 1]["x"]) < W - 120.0:
		pipes.append({"x": W + 20.0, "gy": 70.0 + float(rnd.call()) * (H - 140.0 - GAP), "pass": false})
	for p: Dictionary in pipes:
		p["x"] = float(p["x"]) - SPEED * dt
		if not bool(p["pass"]) and float(p["x"]) + 26.0 < 40.0:
			p["pass"] = true
			score += 1
		if float(p["x"]) < 52.0 and float(p["x"]) + 26.0 > 28.0 and (y - 7.0 < float(p["gy"]) or y + 7.0 > float(p["gy"]) + GAP):
			out.append(_end(rest_mul))
			return out
	if not pipes.is_empty() and float(pipes[0]["x"]) < -30.0:
		pipes.remove_at(0)
	if y > H - 8.0 or y < 6.0:
		out.append(_end(rest_mul))
	return out


func _end(rest_mul: float) -> Dictionary:
	st = "over"
	var hot := cool > 0.0
	var g := 0.0
	if cool <= 0.0 and score > 0:
		g = snappedf(minf(MAX_GAIN, float(score)) * rest_mul, 0.1)
		cool = COOL
	gain = g
	msg = "手指放松下来，远处声音又清楚了" if g > 0.0 else ("手机发烫了，静不下心" if hot and score > 0 else ("这一局结束了。" if score > 0 else ""))
	return {"kind": "end", "gain": g, "score": score}
