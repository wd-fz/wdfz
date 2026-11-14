class_name PatrolPrecursor
extends RefCounted
## Sound first (2026-11-14 horror plan, item 2; docs/plan/中式与西式恐怖及吓人手法.md): the patroller is
## heard before it is seen, in three tiers by the walking distance between it and the player (the patrol
## module's own approach() path, through doors and stairs, never a straight line through walls):
##   far  (14–24 m) a door dragging or slow steps somewhere ahead, every 7–11 s, quiet and muffled;
##   mid  (6–14 m)  slow steps from its direction, every 1.1 s;
##   near (under 6 m, still unseen) heavier steps and, now and then, a breath.
## Only while it walks and is not already drawn in the player's scene (then its own steps play as before).
## The sounds are the ones the false threats use (dread.steps / dread.door), so a single sound proves nothing;
## a real approach keeps its direction and escalates. Only presentation: it changes no rule.

const FAR_M := 24.0
const MID_M := 14.0
const NEAR_M := 6.0
const TIERS := ["", "far", "mid", "near"]

var tier := 0
var _t := 0.0
var _breath := false
var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


static func tier_of(metres: float) -> int:
	if not is_finite(metres) or metres > FAR_M:
		return 0
	return 3 if metres <= NEAR_M else (2 if metres <= MID_M else 1)


## metres: the walking distance (INF when there is none); heard: it walks and is not drawn here.
## Returns the cue to play now: {} or {id, k, tier}.
func step(dt: float, metres: float, heard: bool) -> Dictionary:
	var now := tier_of(metres) if heard else 0
	if now != tier:
		# Closer: play at once; further: let the current pause run out.
		if now > tier:
			_t = 0.0
		tier = now
	if tier == 0:
		_t = 0.0
		return {}
	_t -= dt
	if _t > 0.0:
		return {}
	match tier:
		1:
			_t = _rng.randf_range(7.0, 11.0)
			return {"id": "dread.door" if _rng.randf() < 0.4 else "dread.steps", "k": 0.22, "tier": "far"}
		2:
			_t = 1.1
			return {"id": "dread.steps", "k": 0.45, "tier": "mid"}
		_:
			_t = 0.75
			_breath = not _breath
			if _breath and _rng.randf() < 0.5:
				return {"id": "threat.breath", "k": 0.3, "tier": "near"}
			return {"id": "dread.steps", "k": 0.75, "tier": "near"}
