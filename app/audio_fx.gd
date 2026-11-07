class_name AudioFx
extends Node
## Synthesised placeholder sound (no audio assets ship yet; the Web version's sensory/ and
## audio modules are not ported). Every cue is generated once from plain maths and cached.
## The rule layer never touches this node: the app feeds it a small context each frame and calls
## cue() for events. Sound never changes a rule; it is the "sound first" half of the warnings.

const RATE := 22050
const POOL := 8

var volume := 1.0:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		_apply_volume()
var muted := false:
	set(value):
		muted = value
		_apply_volume()

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}
var _steps: AudioStreamPlayer3D
var _step_t := 0.0
var _beat_t := 0.0
var _patrol_t := 0.0
var _noise := RandomNumberGenerator.new()
var played: Array[String] = []   # last cues, for tests
var enabled := true


func _ready() -> void:
	_noise.seed = 77
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Cue%d" % i
		add_child(p)
		_pool.append(p)
	_steps = AudioStreamPlayer3D.new()
	_steps.name = "PatrolSteps"
	_steps.unit_size = 6.0
	_steps.max_distance = 60.0
	add_child(_steps)
	_apply_volume()


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, muted)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


## One-shot cue. `db` and `pitch` shape a single play.
func cue(id: String, db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled or not is_inside_tree():
		return
	played.append(id)
	if played.size() > 40:
		played.pop_front()
	var stream := stream_of(id)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
	_pool[0].stream = stream
	_pool[0].volume_db = db
	_pool[0].play()


func cue_at(id: String, pos: Vector3, db: float = 0.0) -> void:
	if not enabled or not is_inside_tree():
		return
	played.append(id)
	_steps.global_position = pos
	_steps.stream = stream_of(id)
	_steps.volume_db = db
	_steps.play()


## Ambient loop on or off, with a gain in dB.
func loop(id: String, on: bool, db: float = -12.0) -> void:
	if not is_inside_tree():
		return
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null:
		if not on:
			return
		p = AudioStreamPlayer.new()
		p.name = "Loop_" + id
		p.stream = stream_of(id)
		add_child(p)
		_loops[id] = p
	p.volume_db = db
	if on and not p.playing and enabled:
		p.play()
	elif not on and p.playing:
		p.stop()


func looping(id: String) -> bool:
	return _loops.has(id) and (_loops[id] as AudioStreamPlayer).playing


func stop_all() -> void:
	for p in _pool:
		p.stop()
	for id: String in _loops:
		(_loops[id] as AudioStreamPlayer).stop()
	_steps.stop()


## Per-frame layers. ctx: moving, running, indoors, san, blackout, rain, hiding, patrol_near
## (0..1 closeness while the patroller is in the scene), patrol_pos (Vector3 or null), chase.
func update(delta: float, ctx: Dictionary) -> void:
	if not enabled:
		return
	# Footsteps of the player.
	if bool(ctx.get("moving", false)) and not bool(ctx.get("hiding", false)):
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.33 if bool(ctx.get("running", false)) else 0.52
			cue("step", -16.0 if not bool(ctx.get("running", false)) else -11.0, _noise.randf_range(0.9, 1.1))
	else:
		_step_t = 0.0
	# Heartbeat: SAN below 45 or the patroller close.
	var fear := maxf(clampf((45.0 - float(ctx.get("san", 100.0))) / 45.0, 0.0, 1.0), float(ctx.get("patrol_near", 0.0)) * 0.9)
	if fear > 0.05:
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = lerpf(1.1, 0.5, fear)
			cue("heart", lerpf(-24.0, -6.0, fear))
	else:
		_beat_t = 0.0
	# Patroller steps in space.
	var pp: Variant = ctx.get("patrol_pos")
	if pp is Vector3:
		_patrol_t -= delta
		if _patrol_t <= 0.0:
			_patrol_t = 0.4 if bool(ctx.get("chase", false)) else 0.62
			cue_at("step_heavy", pp, -4.0)
	else:
		_patrol_t = 0.0
	# Ambience.
	loop("hum", bool(ctx.get("indoors", false)) and not bool(ctx.get("blackout", false)), -26.0)
	loop("wind", not bool(ctx.get("indoors", false)), -24.0)
	loop("rain", bool(ctx.get("rain", false)), -14.0)


# ---- synthesis ----

func stream_of(id: String) -> AudioStreamWAV:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStreamWAV = _make(id)
	_streams[id] = s
	return s


func _wav(data: PackedFloat32Array, looped: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(RATE * seconds))
	return a


func _make(id: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	match id:
		"step", "step_heavy":
			var heavy := id == "step_heavy"
			var d := _buf(0.16 if not heavy else 0.22)
			var lp := 0.0
			for i in d.size():
				var t := float(i) / RATE
				lp += ((rng.randf() * 2.0 - 1.0) - lp) * (0.18 if not heavy else 0.09)
				d[i] = lp * exp(-t * (28.0 if not heavy else 18.0)) * (1.6 if not heavy else 2.2) + sin(TAU * (70.0 if heavy else 110.0) * t) * exp(-t * 30.0) * 0.4
			return _wav(d)
		"heart":
			var d := _buf(0.7)
			for beat: float in [0.0, 0.22]:
				for i in d.size():
					var t := float(i) / RATE - beat
					if t >= 0.0 and t < 0.25:
						d[i] += sin(TAU * 52.0 * t) * exp(-t * 18.0) * 0.9
			return _wav(d)
		"thud":
			var d := _buf(0.5)
			var lp := 0.0
			for i in d.size():
				var t := float(i) / RATE
				lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.12
				d[i] = sin(TAU * (90.0 - 60.0 * t) * t) * exp(-t * 9.0) * 0.9 + lp * exp(-t * 20.0) * 0.5
			return _wav(d)
		"bell":
			var d := _buf(2.6)
			for i in d.size():
				var t := float(i) / RATE
				var v := 0.0
				for k in [[220.0, 1.0], [528.0, 0.55], [682.0, 0.4], [924.0, 0.25]]:
					v += sin(TAU * k[0] * t) * k[1]
				d[i] = v * exp(-t * 1.6) * 0.3
			return _wav(d)
		"ding":
			var d := _buf(0.45)
			for i in d.size():
				var t := float(i) / RATE
				d[i] = (sin(TAU * 2100.0 * t) + 0.4 * sin(TAU * 3150.0 * t)) * exp(-t * 9.0) * 0.4
			return _wav(d)
		"drip":
			var d := _buf(0.18)
			for i in d.size():
				var t := float(i) / RATE
				d[i] = sin(TAU * (1500.0 - 4500.0 * t) * t) * exp(-t * 26.0) * 0.6
			return _wav(d)
		"creak":
			var d := _buf(0.55)
			for i in d.size():
				var t := float(i) / RATE
				var f := 180.0 + 90.0 * sin(t * 9.0) + 60.0 * t
				d[i] = (fposmod(f * t, 1.0) * 2.0 - 1.0) * 0.25 * sin(PI * t / 0.55)
			return _wav(d)
		"static":
			var d := _buf(0.9)
			for i in d.size():
				var t := float(i) / RATE
				var gate := 1.0 if sin(t * 38.0) > -0.3 else 0.25
				d[i] = (rng.randf() * 2.0 - 1.0) * 0.3 * gate * sin(PI * t / 0.9)
			return _wav(d)
		"sting":
			var d := _buf(1.0)
			for i in d.size():
				var t := float(i) / RATE
				d[i] = (sin(TAU * 196.0 * t) + sin(TAU * 277.0 * t)) * 0.28 * exp(-t * 2.6) * (1.0 - exp(-t * 40.0))
			return _wav(d)
		"scare":
			var d := _buf(1.3)
			var lp := 0.0
			for i in d.size():
				var t := float(i) / RATE
				lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.3
				d[i] = (lp * 0.5 + sin(TAU * 55.0 * t) * 0.6) * minf(t * 12.0, 1.0) * exp(-t * 2.4)
			return _wav(d)
		"chime":
			var d := _buf(3.0)
			for i in d.size():
				var t := float(i) / RATE
				var v := 0.0
				for k in 3:
					var start := float(k) * 0.55
					var freq: float = [523.25, 659.25, 783.99][k]
					if t >= start:
						v += sin(TAU * freq * (t - start)) * exp(-(t - start) * 1.8)
				d[i] = v * 0.28
			return _wav(d)
		"hum":
			var d := _buf(2.0)
			for i in d.size():
				var t := float(i) / RATE
				d[i] = sin(TAU * 60.0 * t) * 0.5 + sin(TAU * 120.0 * t) * 0.25 + sin(TAU * 180.0 * t) * 0.08
			return _wav(d, true)
		"wind":
			var d := _buf(3.0)
			var lp := 0.0
			for i in d.size():
				var t := float(i) / RATE
				lp += ((rng.randf() * 2.0 - 1.0) - lp) * 0.02
				d[i] = lp * (3.2 + 1.4 * sin(TAU * t / 3.0))
			return _wav(_fade_loop(d), true)
		"engine":
			var d := _buf(2.0)
			for i in d.size():
				var t := float(i) / RATE
				d[i] = (sin(TAU * 42.0 * t) * 0.5 + sin(TAU * 84.0 * t) * 0.25 + (fposmod(21.0 * t, 1.0) - 0.5) * 0.3) * 0.6
			return _wav(d, true)
		"rain":
			var d := _buf(2.0)
			var hp := 0.0
			var prev := 0.0
			for i in d.size():
				var x := rng.randf() * 2.0 - 1.0
				hp = x - prev * 0.6
				prev = x
				d[i] = hp * 0.22
			return _wav(_fade_loop(d), true)
	return null


## Cross-fade the tail into the head so a noise loop has no click.
func _fade_loop(d: PackedFloat32Array) -> PackedFloat32Array:
	var n := mini(2000, d.size() / 4)
	for i in n:
		var k := float(i) / n
		d[i] = d[i] * k + d[d.size() - n + i] * (1.0 - k)
	d.resize(d.size() - n)
	return d
