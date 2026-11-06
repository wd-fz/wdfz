class_name RunClock
extends RefCounted
## Simulation time is independent of wall time and presentation frames.
## The sandbox uses the four phase budgets, without story-specific slow windows.

const DAY_SECONDS := 1200.0
const PHASES := [
	[440.0, 770.0, 360.0],
	[770.0, 1070.0, 360.0],
	[1070.0, 1340.0, 360.0],
	[1340.0, 1500.0, 120.0],
]

var active_seconds := 0.0
var calendar_seconds := 0.0


func advance(delta: float, calendar_running: bool = true) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	active_seconds += delta
	if calendar_running:
		calendar_seconds += delta


func day_index() -> int:
	return int(floor(calendar_seconds / DAY_SECONDS)) + 1


func calendar_minute() -> float:
	var remaining := fmod(calendar_seconds, DAY_SECONDS)
	for phase: Array in PHASES:
		if remaining < float(phase[2]):
			return lerpf(phase[0], phase[1], remaining / float(phase[2]))
		remaining -= float(phase[2])
	return 440.0


func capture() -> Dictionary:
	return {"active_seconds": active_seconds, "calendar_seconds": calendar_seconds}


func restore(data: Dictionary) -> void:
	active_seconds = float(data["active_seconds"])
	calendar_seconds = float(data["calendar_seconds"])
