class_name SchoolCalendar
extends RefCounted
## One calendar per cooperative run; personal schools consume the same minute slices.
var tsec := SchoolModule.START_TSEC
var day := 1
var seconds := 0.0


func advance(dt: float) -> float:
	if not is_finite(dt) or dt <= 0.0: return 0.0
	seconds += dt
	var remaining := dt
	var minutes := 0.0
	var guard := 0
	while remaining > 1e-9 and guard < 64:
		guard += 1
		var slice := SchoolClock.real_time_slice(tsec, remaining, SchoolClock.clock_boundary(tsec), SchoolClock.rate_at(tsec))
		var amount := float(slice["minutes"])
		minutes += amount
		var forward := SchoolClock.forward_slice(tsec, day, amount)
		tsec = float(forward["time"])
		day = int(forward["day"])
		if not slice["nudge"]: remaining -= float(slice["seconds"])
	return minutes


func capture() -> Dictionary:
	return {"tsec": tsec, "day": day, "seconds": seconds}


func restore(data: Dictionary) -> void:
	tsec = float(data["tsec"])
	day = int(data["day"])
	seconds = float(data["seconds"])
