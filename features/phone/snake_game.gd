class_name SnakeGame
extends RefCounted
## The snake game at the lab computer (pcgame.js, reference wd-fz.github.io@0bf508a): a 16×16 board, a
## step every 0.14 s after a 3-second countdown; keys turn at once, a swipe is remembered for the next
## step; you cannot turn straight back. On leaving, a score gives rest: min(20, 6 + 2 × score) scaled by
## the pressure's rest factor. (The activity itself — game minutes, +12 SAN, the cooldown — is the
## facilities' "pc" rest, which starts this game.) Pure rules; the panel draws them.

const N := 16
const STEP := 0.14
const COUNTDOWN := 3.0

var body: Array = []     # Vector2i, head first
var dir := Vector2i(1, 0)
var want: Variant = null
var food := Vector2i(3, 3)
var score := 0
var dead := false
var on := false
var t := 0.0
var cd := 0.0


func start(rnd: Callable) -> void:
	on = true
	dead = false
	score = 0
	t = 0.0
	cd = COUNTDOWN
	body = [Vector2i(8, 8)]
	dir = Vector2i(1, 0)
	want = null
	food = random_food(rnd)


func random_food(rnd: Callable) -> Vector2i:
	return Vector2i(int(float(rnd.call()) * N), int(float(rnd.call()) * N))


func cancel() -> void:
	on = false
	want = null
	t = 0.0
	cd = 0.0


## A swipe or a touch arrow: remembered until the next step (keys win over it).
func turn(d: Vector2i) -> void:
	want = d


## key_dir: the direction held on the keyboard (WASD / arrows), or Vector2i.ZERO. Returns true when the board changed.
func tick(dt: float, key_dir: Vector2i, rnd: Callable) -> bool:
	if not on or dead:
		return false
	if cd > 0.0:
		cd -= dt
		return true
	t += dt
	if t < STEP:
		return false
	t = 0.0
	var nd: Variant = null
	if key_dir != Vector2i.ZERO:
		nd = key_dir
	elif want != null:
		nd = want
		want = null
	# No turning straight back (one wrong swipe would hit yourself).
	if nd != null and not (body.size() > 1 and nd == -dir):
		dir = nd
	var h := (body[0] as Vector2i) + dir
	if h.x < 0 or h.y < 0 or h.x >= N or h.y >= N or body.has(h):
		dead = true
		return true
	body.push_front(h)
	if h == food:
		score += 1
		food = random_food(rnd)
	else:
		body.pop_back()
	return true


## The rest the score earns on leaving.
func gain(rest_mul: float) -> float:
	return snappedf(minf(20.0, 6.0 + score * 2.0) * rest_mul, 0.1) if score > 0 else 0.0
