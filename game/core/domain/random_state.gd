class_name RandomState
extends RefCounted
## JSON numbers round to double precision; PCG uses every bit of its signed 64-bit
## seed/state. Strings keep the exact sequence across save, process exit and load.


static func capture(rng: RandomNumberGenerator) -> Dictionary:
	return {"seed": str(rng.seed), "state": str(rng.state)}


static func valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["seed", "state"]:
		var v: Variant = value.get(key)
		if not v is String or not v.is_valid_int() or str(int(v)) != v:
			return false
	return true


static func restore(rng: RandomNumberGenerator, payload: Dictionary) -> void:
	var saved: Variant = payload.get("random")
	if valid(saved):
		rng.seed = int(saved["seed"])
		rng.state = int(saved["state"])
		return
	# Older Godot saves used numbers. Already rounded bits cannot be recovered,
	# but these files remain readable and their next save uses the exact format.
	if typeof(payload.get("seed")) in [TYPE_INT, TYPE_FLOAT]:
		rng.seed = int(payload["seed"])
	if typeof(payload.get("rng")) in [TYPE_INT, TYPE_FLOAT]:
		rng.state = int(payload["rng"])
