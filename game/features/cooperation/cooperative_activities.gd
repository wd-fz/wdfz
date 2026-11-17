class_name CooperativeActivities
extends RefCounted
## Server runs the actual games. Peers send only taps/directions and a session ID, never a score.
var game := ""
var id := ""
var plane := PlaneGame.new()
var snake := SnakeGame.new()
var rng := RandomNumberGenerator.new()
var flash_at := -100.0
var elapsed := 0.0

func start(kind: String, token: String) -> void:
	game = kind
	id = token
	elapsed = 0
	rng.seed = token.hash()
	if game == "plane": plane.reset()
	else: snake.start(rng.randf)

func close() -> void:
	game = ""
	id = ""
	plane.reset()
	snake.cancel()

func command(data: Dictionary) -> bool:
	if id.is_empty() or data.get("game_id") != id: return false
	if data.get("operation") == "flap" and game == "plane": plane.flap()
	elif data.get("operation") == "turn" and game == "snake":
		if not SaveSchema.is_integer(data.get("x"), -1, 1) or not SaveSchema.is_integer(data.get("y"), -1, 1): return false
		var direction := Vector2i(int(data["x"]), int(data["y"]))
		if absi(direction.x) + absi(direction.y) != 1: return false
		snake.turn(direction)
	else: return false
	return true

func tick(dt: float, rest: float) -> float:
	elapsed += dt
	var gain := 0.0
	if game == "plane":
		for e: Dictionary in plane.tick(dt, rest, rng.randf): gain += float(e["gain"])
	else:
		plane.cool = maxf(0, plane.cool - dt)
		if game == "snake": snake.tick(dt, Vector2i.ZERO, rng.randf)
	return gain

func capture() -> Dictionary:
	var cells: Array = []
	for p: Vector2i in snake.body: cells.append([p.x, p.y])
	return {"game": game, "id": id, "elapsed": elapsed, "flash_at": flash_at, "random": RandomState.capture(rng),
		"plane": {"st": plane.st, "y": plane.y, "vy": plane.vy, "pipes": plane.pipes.duplicate(true), "score": plane.score, "t": plane.t, "cool": plane.cool, "gain": plane.gain, "msg": plane.msg},
		"snake": {"body": cells, "dir": [snake.dir.x, snake.dir.y], "food": [snake.food.x, snake.food.y], "want": [snake.want.x, snake.want.y] if snake.want != null else null, "score": snake.score, "dead": snake.dead, "on": snake.on, "t": snake.t, "cd": snake.cd}}

static func display(data: Dictionary, plane_view: PlaneGame, snake_view: SnakeGame) -> void:
	for key: String in ["st", "y", "vy", "pipes", "score", "t", "cool", "gain", "msg"]: plane_view.set(key, data["plane"][key])
	var s: Dictionary = data["snake"]
	for key: String in ["score", "dead", "on", "t", "cd"]: snake_view.set(key, s[key])
	snake_view.body = []
	for p: Array in s["body"]: snake_view.body.append(Vector2i(int(p[0]), int(p[1])))
	snake_view.dir = Vector2i(int(s["dir"][0]), int(s["dir"][1]))
	snake_view.food = Vector2i(int(s["food"][0]), int(s["food"][1]))
	snake_view.want = Vector2i(int(s["want"][0]), int(s["want"][1])) if s["want"] != null else null

func restore(data: Dictionary) -> void:
	if data.is_empty(): return
	display(data, plane, snake)
	game = String(data["game"])
	id = String(data["id"])
	elapsed = float(data["elapsed"])
	flash_at = float(data["flash_at"])
	RandomState.restore(rng, data)
