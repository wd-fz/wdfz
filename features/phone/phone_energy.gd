class_name PhoneEnergy
extends RefCounted
## Battery, wireless cracking, the container download and the automatic power-on threshold, split
## by simulated seconds (domain/phone-energy.js, reference wd-fz.github.io@0bf508a). Pure rules.

const WIRELESS_SIGNAL_SECONDS := 15.0
const EPS := 1e-8


static func fresh() -> Dictionary:
	return {"initialized": false, "battery": 100.0, "powered": true, "warn20": false, "warn5": false, "network": false,
		"wireless": {"status": "idle", "elapsed": 0.0, "target": 0.0}, "download": {"status": "idle", "elapsed": 0.0, "target": 60.0}}


## Seconds until the next exposure of the cracking (every 15 run-seconds).
static func next_signal_in(w: Dictionary) -> float:
	return (floor((float(w["elapsed"]) + EPS) / WIRELESS_SIGNAL_SECONDS) + 1.0) * WIRELESS_SIGNAL_SECONDS - float(w["elapsed"])


## Net charge per second. c: held, classroom, computer, tech.
static func rate(d: Dictionary, c: Dictionary) -> float:
	var running: bool = bool(d["powered"]) and bool(c.get("held", false)) and d["wireless"]["status"] == "running"
	var gain := 0.5 if bool(c.get("classroom", false)) else (1.0 / 6.0 if bool(c.get("computer", false)) else 0.0)
	return gain - (1.0 / 6.0) * (2.0 if running else 1.0) * (2.0 if bool(c.get("tech", false)) else 1.0)


## Advance `seconds`; returns events: wirelessSignal, connected, downloaded, low20, low5, off, on.
static func advance(d: Dictionary, seconds: float, c: Dictionary) -> Array:
	var events: Array = []
	var left := seconds
	if not bool(d["initialized"]) or not (seconds > 0.0):
		return events
	var guard := 0
	while left > EPS and guard < 1000:
		guard += 1
		var tasks: bool = bool(c.get("held", false)) and bool(d["powered"])
		var task: Variant = null
		if tasks:
			if d["wireless"]["status"] == "running":
				task = d["wireless"]
			elif d["download"]["status"] == "running":
				task = d["download"]
		var r := rate(d, c)
		var span := left
		var signal_at := -1.0
		if task != null:
			span = minf(span, maxf(0.0, float(task["target"]) - float(task["elapsed"])))
		if task != null and task == d["wireless"]:
			signal_at = (floor((float(task["elapsed"]) + EPS) / WIRELESS_SIGNAL_SECONDS) + 1.0) * WIRELESS_SIGNAL_SECONDS
			span = minf(span, signal_at - float(task["elapsed"]))
		if r < 0.0 and float(d["battery"]) > 0.0:
			span = minf(span, float(d["battery"]) / -r)
		if r > 0.0 and not bool(d["powered"]) and float(d["battery"]) < 5.0:
			span = minf(span, (5.0 - float(d["battery"])) / r)
		if task != null:
			task["elapsed"] = minf(float(task["target"]), float(task["elapsed"]) + span)
		d["battery"] = clampf(float(d["battery"]) + r * span, 0.0, 100.0)
		left -= span
		if signal_at >= 0.0 and float(task["elapsed"]) >= signal_at - EPS:
			events.append("wirelessSignal")
		if task != null and float(task["elapsed"]) >= float(task["target"]) - EPS:
			task["elapsed"] = float(task["target"])
			task["status"] = "complete"
			if task == d["wireless"]:
				d["network"] = true
				d["download"]["status"] = "running"
				events.append("connected")
			else:
				events.append("downloaded")
		if float(d["battery"]) <= 20.0 + EPS and not bool(d["warn20"]):
			d["warn20"] = true
			events.append("low20")
		if float(d["battery"]) <= 5.0 + EPS and not bool(d["warn5"]):
			d["warn5"] = true
			events.append("low5")
		if float(d["battery"]) <= EPS and bool(d["powered"]):
			d["battery"] = 0.0
			d["powered"] = false
			events.append("off")
		if float(d["battery"]) >= 5.0 - EPS and not bool(d["powered"]) and r > 0.0:
			d["powered"] = true
			events.append("on")
		if span <= EPS and task == null:
			break
	return events
