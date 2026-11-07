class_name SensoryRules
extends RefCounted
## How low SAN feels, ported from the Web version (reference wd-fz.github.io@0bf508a,
## domain/sensory.js SensoryRules): no SAN number on the HUD; below 60 the picture warps, narrows,
## blurs and drains of colour, and very low it blinks black. Static channels (tunnel, blur, drain)
## always show the state; moving ones follow the distortion setting; real danger softens all to 35 %,
## a takeover (driving, a terminal) turns it off. Pure functions; the UI draws them.


static func target(san: float) -> float:
	return clampf((60.0 - clampf(san, 0.0, 100.0)) / 60.0, 0.0, 1.0)


## Ease towards the target: quick to get worse (0.35 s), slow to get better (2 s).
static func step(previous: float, san: float, dt: float) -> float:
	var t := target(san)
	if previous < 0.0:
		return t
	return previous + (t - previous) * (1.0 - exp(-maxf(0.0, dt) / (0.35 if t > previous else 2.0)))


## opts: distortion (0 off, 1 reduced, 2 full), takeover, threat, time, reduce_flash, chase.
static func view(body: float, opts: Dictionary = {}) -> Dictionary:
	var d := int(opts.get("distortion", 2))
	var k := 0.0 if d == 0 else (0.35 if d == 1 else 1.0)
	var safe := 0.0 if bool(opts.get("takeover", false)) else (0.35 if bool(opts.get("threat", false)) else 1.0)
	var t := float(opts.get("time", 0.0))
	var hunt := 0.5 + 0.5 * sin(t * 0.83 + 1.7 * sin(t * 0.29))
	return {"warp": pow(body, 1.5) * k * safe, "tunnel": pow(body, 1.25) * safe, "blur": body * safe, "focus": body * body * k * hunt * safe,
		"drain": minf(1.0, body * 1.15) * safe, "halo": body * safe, "pulse": k * safe if body > 0.35 else 0.0,
		"ghost": minf(1.0, (body - 0.45) / 0.45) * k * safe if body > 0.45 else 0.0,
		"flicker": clampf((body - 0.35) / 0.25, 0.0, 1.0) * (0.5 if bool(opts.get("reduce_flash", false)) else 1.0) * safe,
		"flicker_gap": 14.0 - 10.5 * clampf((body - 0.35) / 0.65, 0.0, 1.0) if body > 0.35 else 0.0,
		"bpm": maxf(124.0 if bool(opts.get("chase", false)) else 0.0, 70.0 + body * 65.0 if body > 0.35 else 0.0), "breath": body}


## One black-out: [start, fully black until, recovery] segments; rnd is a presentation random.
static func blink_plan(body: float, rnd: RandomNumberGenerator) -> Array:
	if body >= 0.75 and rnd.randf() < 0.3:
		return [[0.0, 0.35 + 0.25 * rnd.randf(), 0.4]]
	var out: Array = []
	var at := 0.0
	var n := 2 if body >= 0.6 and rnd.randf() < 0.5 else 1
	for _i in n:
		var length := 0.07 + 0.07 * rnd.randf()
		out.append([at, at + length, 0.06])
		at += length + 0.1 + 0.06 * rnd.randf()
	return out


static func blink_at(plan: Array, t: float) -> float:
	var v := 0.0
	for seg: Array in plan:
		if t >= float(seg[0]) and t < float(seg[1]):
			v = 1.0
		elif t >= float(seg[1]) and t < float(seg[1]) + float(seg[2]):
			v = maxf(v, 1.0 - (t - float(seg[1])) / float(seg[2]))
	return v


static func blink_end(plan: Array) -> float:
	var m := 0.0
	for seg: Array in plan:
		m = maxf(m, float(seg[1]) + float(seg[2]))
	return m
