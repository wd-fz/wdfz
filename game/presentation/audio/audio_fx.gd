class_name AudioFx
extends Node
## Sound, ported from the Web version (reference wd-fz.github.io@0bf508a): audio.js (SFX:
## category buses → master → compressor, reverb by place, the continuous beds, step surfaces,
## stingers and the small ambient events), modules/sensory (heart and breath) and the one-shot
## recipes of sound-bank.js, baked by tools/audio_bake/bake.cjs into assets/audio with the old
## loudness calibration. Every play re-picks a baked take and adds the recipe's pitch and gain
## variation. The rule layer never touches this node: the app feeds it a context each frame and
## calls play() for events. Sound never changes a rule.

const INDEX := "res://assets/audio/index.json"
const POOL := 14
const POOL_3D := 10
## audio.js SPACES (the "real" reverb per place) mapped onto Godot's reverb.
const SPACES := {
	"room": {"size": 0.35, "damp": 0.6, "pre": 8.0},
	"hall": {"size": 0.65, "damp": 0.45, "pre": 12.0},
	"garage": {"size": 0.85, "damp": 0.35, "pre": 20.0},
	"bell": {"size": 0.95, "damp": 0.45, "pre": 30.0},
	"out": {"size": 0.2, "damp": 0.15, "pre": 45.0},
	"dorm": {"size": 0.25, "damp": 0.55, "pre": 6.0}}
const STINGERS := ["dread.knock", "dread.whisper", "dread.steps", "distant.slam", "distant.tinnitus", "distant.aah",
	"dread.chair", "distant.ball", "distant.giggle", "dread.door", "dread.run"]
const MEL := [[220.0, 261.6, 293.7, 311.1, 392.0, 440.0, 523.3], [207.7, 246.9, 277.2, 311.1, 370.0, 415.3, 493.9]]
const BUSES := ["Sfx", "SfxSoft", "SfxMuffled", "Ui", "Beds"]

var volume := 0.7:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		_apply_volume()
var muted := false:
	set(value):
		muted = value
		_apply_volume()
## The old "音乐／环境" switch: beds, melody and ambient events (not the game's warning sounds).
var ambience := true
var enabled := true
var played: Array[String] = []   # last plays, for tests
var captions := SoundCaptions.new()
## Captions are published only in play (not on the menu, dead, paused or in a cutscene).
var captions_live := false
## Phone, lesson or terminal open: only the most urgent captions get through.
var captions_busy := false

var _index: Dictionary = {}
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool3: Array[AudioStreamPlayer3D] = []
var _audition: AudioStreamPlayer
var _audition_rng := RandomNumberGenerator.new()
var _preview_voices: Array[AudioStreamPlayer] = []
var _next := 0
var _next3 := 0
var _beds: Dictionary = {}      # name → {player, gain}
var _delayed: Array = []        # [time, id, opts]
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _foot := 0
var _step_t := 0.0
var _beat_t := 0.0
var _breath_t := 0.0
## Seconds since the last heartbeat and breath sound started (the picture follows the same beat, muted or not).
var pulse_t := 9.0
var inhale_t := 9.0
var _patrol_t := 0.0
var _next_mel := 4.0
var _next_cricket := 1.0
var _next_drip := 1.0
var _next_stinger := 30.0
var _next_indoor := 2.0
var _next_menu := 2.5
var _duck_until := 0.0
var _space := ""
var _last_period := ""
var _void_ping := 8.0
var _void_moan := 35.0


func _ready() -> void:
	_rng.randomize()
	var f := FileAccess.open(INDEX, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_index = parsed
	_make_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Sfx3D%d" % i
		add_child(p3)
		_pool3.append(p3)
	_apply_volume()


# ---- buses: category → (muffled) → Sfx (reverb) → Master (compressor) ----

func _make_buses() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
	AudioServer.set_bus_send(AudioServer.get_bus_index("Sfx"), "Master")
	AudioServer.set_bus_send(AudioServer.get_bus_index("SfxSoft"), "Sfx")
	AudioServer.set_bus_send(AudioServer.get_bus_index("SfxMuffled"), "Sfx")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Ui"), "Master")
	AudioServer.set_bus_send(AudioServer.get_bus_index("Beds"), "Master")
	# Muffled: audio.js chain() lowpass 350 + 9000·lp² (lp 0.35–0.55 behind a wall; 0.6–0.7 softer).
	_ensure_effect("SfxMuffled", "AudioEffectLowPassFilter", func() -> AudioEffect:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 1800.0
		return lp)
	_ensure_effect("SfxSoft", "AudioEffectLowPassFilter", func() -> AudioEffect:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 3600.0
		return lp)
	_ensure_effect("Sfx", "AudioEffectReverb", func() -> AudioEffect:
		var r := AudioEffectReverb.new()
		r.dry = 1.0
		r.wet = 0.15
		return r)
	_ensure_effect("Beds", "AudioEffectReverb", func() -> AudioEffect:
		var r := AudioEffectReverb.new()
		r.dry = 1.0
		r.wet = 0.12
		r.room_size = 0.7
		return r)
	# Master: the old DynamicsCompressor (threshold −18 dB, ratio 4, attack 4 ms, release 250 ms).
	_ensure_effect("Master", "AudioEffectCompressor", func() -> AudioEffect:
		var c := AudioEffectCompressor.new()
		c.threshold = -18.0
		c.ratio = 4.0
		c.attack_us = 4000.0
		c.release_ms = 250.0
		return c)


func _ensure_effect(bus: String, kind: String, make: Callable) -> void:
	var b := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(b):
		if AudioServer.get_bus_effect(b, i).get_class() == kind:
			return
	AudioServer.add_bus_effect(b, make.call())


func _reverb() -> AudioEffectReverb:
	var b := AudioServer.get_bus_index("Sfx")
	for i in AudioServer.get_bus_effect_count(b):
		var e := AudioServer.get_bus_effect(b, i)
		if e is AudioEffectReverb:
			return e
	return null


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, muted)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


# ---- the bank ----

func has(id: String) -> bool:
	return (_index.get("sfx", {}) as Dictionary).has(id)


func ids() -> Array:
	return (_index.get("sfx", {}) as Dictionary).keys()


func _stream(rel: String, looped: bool) -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var s: AudioStream = load("res://assets/audio/" + rel) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = looped
	_streams[rel] = s
	return s


func stream_of(id: String) -> AudioStream:
	var d: Dictionary = (_index.get("sfx", {}) as Dictionary).get(id, {})
	if d.is_empty():
		return null
	return _stream("sfx/" + String((d["files"] as Array)[0]["file"]), false)


## A separate voice and RNG keep developer audition out of world sounds and captions.
func audition(id: String) -> bool:
	var d: Dictionary = _index.get("sfx",{}).get(id,{})
	if d.is_empty() or not is_inside_tree():
		return false
	if _audition == null:
		_audition_rng.randomize()
		_audition = AudioStreamPlayer.new()
		_audition.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_audition)
	var files: Array = d["files"]
	var take: Dictionary = files[_audition_rng.randi()%files.size()]
	var vary: Dictionary = d.get("vary",{})
	_audition.stop()
	_audition.stream = _stream("sfx/"+String(take["file"]),false)
	_audition.bus = "Ui" if d["cat"] == "ui" else "Sfx"
	_audition.volume_db = float(take["db"])+linear_to_db(maxf(.001,1+_audition_rng.randf_range(-1,1)*float(vary.get("g",0))))
	_audition.pitch_scale = maxf(.05,1+_audition_rng.randf_range(-1,1)*float(vary.get("p",0)))
	_audition.play()
	return true


func stop_audition() -> void:
	if is_instance_valid(_audition):
		_audition.stop()


## One recipe. opts (as in sound-player.js): k loudness, pan −1…1, lp muffled (1 = clear), pitch,
## at delay in seconds; pos (Vector3) plays it at a place in the world instead of a pan.
func play(id: String, opts: Dictionary = {}) -> bool:
	played.append(id)
	if played.size() > 60:
		played.pop_front()
	if not enabled or not is_inside_tree():
		return false
	var d: Dictionary = (_index.get("sfx", {}) as Dictionary).get(id, {})
	if d.is_empty():
		return false
	var at := float(opts.get("at", 0.0))
	if captions_live and not bool(opts.get("captioned", false)):
		captions.publish(id, _place_of(opts), captions_busy)
	if at > 0.0:
		var o := opts.duplicate()
		o.erase("at")
		o["captioned"] = true
		_delayed.append([_t + at, id, o])
		return true
	var files: Array = d["files"]
	if id=="event.bellEnd" and opts.has("tail"):
		for variant: Dictionary in _index.get("bell_tails",[]):
			if is_equal_approx(variant["tail"],float(opts["tail"])) and is_equal_approx(variant["tailLength"],float(opts.get("tailLength",1))):
				files = variant["files"]
				break
	var take: Dictionary = files[_rng.randi() % files.size()]
	var vary: Dictionary = d["vary"]
	var k := maxf(0.0, float(opts.get("k", 1.0))) * (1.0 + (_rng.randf() * 2.0 - 1.0) * float(vary.get("g", 0.0)))
	if k < 0.0005:
		return true
	var db := float(take["db"]) + linear_to_db(k)
	var pitch := maxf(0.05, float(opts.get("pitch", 1.0)) * (1.0 + (_rng.randf() * 2.0 - 1.0) * float(vary.get("p", 0.0))))
	var lp := float(opts.get("lp", 1.0))
	var bus := "Ui" if d["cat"] == "ui" else ("SfxMuffled" if lp < 0.5 else ("SfxSoft" if lp < 0.98 else "Sfx"))
	var stream := _stream("sfx/" + String(take["file"]), false)
	var pan := float(opts.get("pan", 0.0))
	var pos: Variant = opts.get("pos")
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null and (pos is Vector3 or absf(pan) > 0.01):
		var p3 := _pool3[_next3]
		_next3 = (_next3 + 1) % _pool3.size()
		p3.stop()
		p3.stream = stream
		p3.bus = bus
		p3.pitch_scale = pitch
		if pos is Vector3:
			p3.global_position = pos
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			p3.unit_size = float(opts.get("unit", 5.0))
			p3.max_distance = 80.0
			p3.volume_db = db
		else:
			var az := clampf(pan, -1.0, 1.0) * PI * 0.5
			p3.global_position = cam.global_position + cam.global_basis * (Vector3(sin(az), 0.0, -cos(az)) * 1.6)
			p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
			p3.max_distance = 0.0
			p3.volume_db = db
		p3.play()
		return true
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = stream
	p.bus = bus
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return true


## Fade out every playing one-shot of a category (or all): SoundPlayer.stop.
func stop(cat: String = "") -> void:
	for p in _pool:
		if p.playing and (cat == "" or _cat_of(p.stream) == cat):
			p.stop()
	for p3 in _pool3:
		if p3.playing and (cat == "" or _cat_of(p3.stream) == cat):
			p3.stop()
	_delayed = _delayed.filter(func(e: Array) -> bool: return cat != "" and String((_index["sfx"][e[1]] as Dictionary)["cat"]) != cat)


func _cat_of(s: AudioStream) -> String:
	if s == null:
		return ""
	var file := s.resource_path.get_file()
	var id := file.substr(0, file.rfind(".", file.rfind(".") - 1))
	return String((_index.get("sfx", {}) as Dictionary).get(id, {}).get("cat", ""))


func stop_all() -> void:
	stop()
	stop_audition()
	captions.reset()
	for name: String in _beds:
		var b: Dictionary = _beds[name]
		(b["player"] as AudioStreamPlayer).stop()
		b["gain"] = 0.0


func _exit_tree() -> void:
	# Stop looping playbacks explicitly before the audio server shuts down.
	stop_all()
	for voice in get_children():
		if voice is AudioStreamPlayer or voice is AudioStreamPlayer3D:
			voice.stream = null
	_streams.clear()


func playing_ids() -> Array:
	var out: Array = []
	for p in _pool:
		if p.playing and p.stream != null:
			out.append(p.stream.resource_path.get_file())
	for p3 in _pool3:
		if p3.playing and p3.stream != null:
			out.append(p3.stream.resource_path.get_file())
	return out


## The caption's place words from the play options (pan, behind, distance, muffled).
func _place_of(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	var place: Dictionary = o.get("place", {})
	if place.is_empty():
		if absf(float(o.get("pan", 0.0))) > 0.25:
			place["pan"] = float(o["pan"])
		if float(o.get("lp", 1.0)) < 0.5:
			place["muffled"] = true
		var pos: Variant = o.get("pos")
		var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
		if pos is Vector3 and cam != null:
			var to: Vector3 = (pos as Vector3) - cam.global_position
			place["m"] = to.length()
			place["behind"] = (-cam.global_basis.z).dot(to.normalized()) < -0.2
			var side := cam.global_basis.x.dot(to.normalized())
			if absf(side) > 0.25:
				place["pan"] = side
	o["place"] = place
	return o


# ---- the old SFX API ----

## A step on a surface (stepSound): feet alternate in pitch and a little in pan.
func step_on(surface: String, k: float = 1.0, opts: Dictionary = {}) -> void:
	_foot = 1 - _foot
	var o := {"k": k, "pitch": 0.97 if _foot == 1 else 1.0, "pan": clampf(float(opts.get("pan", 0.0)) + (0.05 if _foot == 1 else -0.05), -1.0, 1.0)}
	for key: String in ["lp", "pos", "at", "patrol", "self_step"]:
		if opts.has(key):
			o[key] = opts[key]
	play("step." + surface if has("step." + surface) else "step.tile", o)
	if surface == "court" and _rng.randf() < 0.12:
		play("step.squeak", {"k": k, "pan": o["pan"], "at": float(opts.get("at", 0.0)) + 0.02})
	if bool(opts.get("wet", false)):
		play("step.wet", o)


## tune: AtmosModule.bell_tune (A5) — only the last note sinks / lengthens as the days pass.
func school_bell(kind: String, outdoor: bool, tune: Dictionary = {}) -> void:
	var v := 0.45 if outdoor else 1.0
	var opts := {"k": v, "lp": 0.6 if v < 0.7 else 1.0}
	if not tune.is_empty():
		opts["tail"] = float(tune.get("tail",1))
		opts["tailLength"] = float(tune.get("tailLength",1))
		opts["caption"] = String(tune["caption"])
	play("event.bellStart" if kind == "start" else "event.bellEnd", opts)


## A caption for a sound that has no sample of its own (the hush).
func note_caption(id: String, opts: Dictionary = {}) -> void:
	if captions_live:
		captions.publish(id, opts, captions_busy)


func anomaly_start(id: String) -> void:
	play("anomaly.base")
	play("anomaly." + id)
	if id == "cola":
		play("foley.colaRattle", {"pan": _rng.randf_range(-0.6, 0.6)})


func death(fx: String) -> void:
	play("death.base")
	if not play("death." + fx):
		play("death.generic")


func thunder(delay: float, strength: float, muffled: bool) -> void:
	var s := clampf(strength, 0.2, 1.0)
	play("event.thunder" if s > 0.7 else "event.thunderFar", {"at": delay, "k": s, "lp": 0.45 if muffled else 1.0})


func achieve(tier: String) -> void:
	play("ui.achieve." + ({"n": "normal", "e": "elite", "p": "epic", "h": "hidden"} as Dictionary).get(tier, "normal"))


## 骤静: the beds drop almost to nothing for a few seconds.
func duck(sec: float) -> void:
	_duck_until = _t + maxf(0.5, sec)


func ducking() -> bool:
	return _t < _duck_until


# ---- beds (audio.js buildLayers / tick) ----

func _bed(name: String, target: float, tc: float, dt: float) -> void:
	var b: Dictionary = _beds.get(name, {})
	if b.is_empty():
		if target <= 0.0001:
			return
		var info: Dictionary = (_index.get("beds", {}) as Dictionary).get(name, {})
		if info.is_empty():
			return
		var p := AudioStreamPlayer.new()
		p.name = "Bed_" + name
		p.bus = "Beds"
		p.stream = _stream("beds/" + name + ".ogg", true)
		add_child(p)
		b = {"player": p, "gain": 0.0, "db": float(info["db"])}
		_beds[name] = b
	var g := float(b["gain"])
	g = target + (g - target) * exp(-dt / maxf(0.01, tc))
	b["gain"] = g
	var pl: AudioStreamPlayer = b["player"]
	if g < 0.0003 and target <= 0.0001:
		if pl.playing:
			pl.stop()
		return
	pl.volume_db = float(b["db"]) + linear_to_db(maxf(g, 0.00001))
	if not pl.playing and enabled:
		pl.play(_rng.randf() * maxf(0.0, pl.stream.get_length() - 0.1))


func bed_gain(name: String) -> float:
	return float((_beds.get(name, {}) as Dictionary).get("gain", 0.0))


func bed_playing(name: String) -> bool:
	return _beds.has(name) and ((_beds[name] as Dictionary)["player"] as AudioStreamPlayer).playing


## The space for the reverb and its amount (spaceWet / spaceKind).
func _set_space(kind: String, wet: float) -> void:
	var r := _reverb()
	if r == null:
		return
	r.wet = clampf(wet * 0.2, 0.0, 0.5)
	if kind == _space:
		return
	_space = kind
	var s: Dictionary = SPACES.get(kind, SPACES["room"])
	r.room_size = float(s["size"])
	r.damping = float(s["damp"])
	r.predelay_msec = float(s["pre"])


## Per frame. ctx: menu, dead, scene, out, night (0..1), surface, san, viol, anomaly (id or ""),
## shelter (indoors while it rains), moving, running, hiding, body (sensory 0..1), bpm, chase,
## threat, patrol_pos (Vector3 or null), patrol_behind, big (a large floor), blackout, period.
func update(delta: float, ctx: Dictionary) -> void:
	_t += delta
	captions.tick(delta)
	captions_live = not bool(ctx.get("menu", false)) and not bool(ctx.get("dead", false))
	captions_busy = bool(ctx.get("busy", false))
	for e: Array in _delayed.duplicate():
		if _t >= float(e[0]):
			_delayed.erase(e)
			play(String(e[1]), e[2])
	if not enabled:
		return
	# The dismissal bell: one 12-second section after another while it rings.
	if _legacy_loops.has("dismissal") and _t >= float(_legacy_loops["dismissal"]):
		_legacy_loops["dismissal"] = _t + 12.0
		play("event.dismissal")
	var duck_k := 0.05 if ducking() else 1.0
	if bool(ctx.get("menu", false)):
		_menu(delta, duck_k)
		return
	var on := ambience and not bool(ctx.get("dead", false))
	var scene := String(ctx.get("scene", ""))
	if scene == "lift_dream":
		_maze_audio(delta, ctx, on, duck_k)
		return
	_bed("void", 0.0, 0.5, delta)
	var out := bool(ctx.get("out", false))
	var night := float(ctx.get("night", 0.0))
	var an := String(ctx.get("anomaly", ""))
	var san := clampf(float(ctx.get("san", 100.0)), 0.0, 100.0)
	var tension := clampf((0.55 if an != "" else 0.0) + (100.0 - san) / 160.0 + float(ctx.get("viol", 0.0)) / 220.0, 0.0, 1.0)
	var garage := scene == "garage1"
	# Reverb follows the place (spaceWet / SPACES).
	var kind := "out" if out else ("garage" if garage else ("bell" if scene == "bell1" else ("out" if scene == "teach6" else ("dorm" if scene.begins_with("dorm") else ("hall" if bool(ctx.get("big", false)) else "room")))))
	_set_space(kind, 0.35 if out else (1.7 if garage else (1.9 if scene == "bell1" else (0.4 if scene == "teach6" else (1.15 if bool(ctx.get("big", false)) else 0.9)))))
	# The pad: root by place, calm ↔ tense by tension; the tension cluster above 0.45.
	var root := "garage" if garage else ("night" if out and night > 0.5 else ("day" if out else "in"))
	var pad := (0.045 + 0.05 * tension) * duck_k if on else 0.0
	var mix := clampf((tension - 0.15) / 0.7, 0.0, 1.0)
	for r: String in ["in", "day", "night", "garage"]:
		_bed("pad_%s_calm" % r, pad * (1.0 - mix) if r == root else 0.0, 1.5, delta)
		_bed("pad_%s_tense" % r, pad * mix if r == root else 0.0, 1.5, delta)
	_bed("pad_menu", 0.0, 0.6, delta)
	_bed("tension", maxf(0.0, tension - 0.45) * 0.05 * duck_k if on else 0.0, 0.8, delta)
	var rain_on := on and an in ["rain", "raindots"]
	var cover := rain_on and not out
	_bed("wind", ((0.020 + 0.012 * night + (0.02 if rain_on else 0.0)) if on and out else (0.03 if on and scene == "teach6" else 0.0)) * duck_k, 1.0, delta)
	_bed("rain", (0.03 if cover else 0.11) if rain_on else 0.0, 0.6, delta)
	_bed("rain2", (0.005 if cover else 0.035) if rain_on else 0.0, 0.6, delta)
	var hum_on := on and not out and not garage and scene != "bell1" and scene != "teach6" and not bool(ctx.get("blackout", false))
	_bed("hum", (0.010 + 0.006 * absf(sin(_t * 0.7))) * duck_k if hum_on else 0.0, 0.5, delta)
	_bed("rumble", (0.09 if on and garage else (0.12 if on and an == "shifting" else 0.0)) * duck_k, 0.8, delta)
	_body(delta, ctx)
	_steps(delta, ctx)
	_patrol(delta, ctx)
	if not on or ducking():
		return
	_ambient(delta, ctx, out, night, garage, an, tension, rain_on, cover)


func _maze_audio(dt: float, ctx: Dictionary, on: bool, duck_k: float) -> void:
	for name: String in _beds.keys():
		if name != "void":
			_bed(name, 0.0, 0.4, dt)
	_bed("void", 0.075 * duck_k if on else 0.0, 0.5, dt)
	_set_space("hall", 1.7)
	_body(dt, ctx)
	var local := ctx.duplicate()
	local["surface"] = "void"
	_steps(dt, local)
	if not on or ducking():
		return
	_void_ping -= dt
	_void_moan -= dt
	if _void_ping <= 0.0:
		_void_ping = _rng.randf_range(9.0, 24.0)
		play("void.ping", {"pan": _rng.randf_range(-0.8, 0.8), "pitch": _rng.randf_range(0.65, 1.45)})
	if _void_moan <= 0.0:
		_void_moan = _rng.randf_range(40.0, 90.0)
		play("void.moan", {"pan": _rng.randf_range(-0.6, 0.6)})


func _menu(delta: float, duck_k: float) -> void:
	for name: String in _beds:
		if name != "pad_menu":
			_bed(name, 0.0, 0.8, delta)
	_bed("pad_menu", 0.058 * duck_k if ambience else 0.0, 2.4, delta)
	_set_space("hall", 1.6)
	if not ambience:
		return
	_next_menu -= delta
	if _next_menu <= 0.0:
		_next_menu = _rng.randf_range(6.0, 12.0)
		var sc: Array = MEL[0]
		for j in 2 + _rng.randi() % 3:
			var f := float(sc[_rng.randi() % sc.size()]) * (2.0 if _rng.randf() < 0.25 else 1.0)
			play("music.box", {"pitch": f / 440.0, "at": j * _rng.randf_range(0.45, 0.9)})


## Heart and breath (modules/sensory): the heart at the sensory rate, breath when shaken.
func _body(delta: float, ctx: Dictionary) -> void:
	var body := float(ctx.get("body", 0.0))
	var bpm := float(ctx.get("bpm", 0.0))
	pulse_t += delta
	inhale_t += delta
	if bpm > 0.0:
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = 60.0 / bpm
			pulse_t = 0.0
			play("threat.heartPat" if bool(ctx.get("chase", false)) else "threat.heartLow", {"k": 0.35 + body * 0.35})
	else:
		_beat_t = 0.0
	_breath_t -= delta
	if body > 0.08 and _breath_t <= 0.0:
		_breath_t = 6.0 - body * 2.0
		inhale_t = 0.0
		play("threat.breath", {"k": 0.25 if bool(ctx.get("threat", false)) else 0.45 + body * 0.25})


func _steps(delta: float, ctx: Dictionary) -> void:
	if bool(ctx.get("moving", false)) and not bool(ctx.get("hiding", false)):
		_step_t -= delta
		if _step_t <= 0.0:
			var run := bool(ctx.get("running", false))
			_step_t = 0.33 if run else 0.52
			var wet := bool(ctx.get("out", false)) and String(ctx.get("anomaly", "")) in ["rain", "raindots"]
			step_on(String(ctx.get("surface", "tile")), 1.35 if run else 1.0, {"wet": wet, "self_step": true})
			# A revisit's echo: the same step again, quiet, behind and late (dread.js DREAD.echo).
			if bool(ctx.get("echo", false)):
				step_on(String(ctx.get("surface", "tile")), 0.32, {"pan": 0.25, "lp": 0.55, "at": 0.19, "self_step": true})
	else:
		_step_t = 0.0


## The patroller's steps in space (patStep): louder when locked, muffled behind.
func _patrol(delta: float, ctx: Dictionary) -> void:
	var pp: Variant = ctx.get("patrol_pos")
	if pp is Vector3:
		_patrol_t -= delta
		if _patrol_t <= 0.0:
			var locked := bool(ctx.get("chase", false))
			_patrol_t = 0.4 if locked else 0.62
			step_on(String(ctx.get("surface", "tile")), 1.5 if locked else 1.1, {"pos": pp, "patrol": true, "lp": 0.55 if bool(ctx.get("patrol_behind", false)) else 1.0})
	else:
		_patrol_t = 0.0


func _ambient(delta: float, ctx: Dictionary, out: bool, night: float, garage: bool, an: String, tension: float, rain_on: bool, cover: bool) -> void:
	_next_mel -= delta
	if _next_mel <= 0.0:
		_next_mel = _rng.randf_range(5.0, 11.0) * (1.0 - tension * 0.4)
		var sc: Array = MEL[1 if tension > 0.5 else 0]
		for j in 1 + _rng.randi() % 3:
			var f := float(sc[_rng.randi() % sc.size()]) * (2.0 if _rng.randf() < 0.3 else 1.0)
			play("music.box", {"pitch": f / 440.0, "at": j * _rng.randf_range(0.35, 0.7)})
	if out and night > 0.6 and not rain_on:
		_next_cricket -= delta
		if _next_cricket <= 0.0:
			_next_cricket = _rng.randf_range(0.25, 1.1)
			if sin(_t * 0.05) > -0.7:
				play("world.cricket", {"pitch": _rng.randf_range(0.9, 1.1), "pan": _rng.randf_range(-0.8, 0.8)})
	if garage or an == "leak":
		_next_drip -= delta
		if _next_drip <= 0.0:
			_next_drip = _rng.randf_range(0.8, 3.0) if garage else _rng.randf_range(0.3, 0.8)
			play("world.drip", {"pan": _rng.randf_range(-0.7, 0.7)} if garage else {"k": 1.3, "pan": _rng.randf_range(-0.4, 0.4)})
	elif rain_on and not cover and bool(ctx.get("brolly", false)):
		# audio.js: under the open umbrella the rain patters on the canopy (about 28 a second).
		var n := floori(delta * 28.0 + _rng.randf())
		for _i in n:
			play("world.patter", {"at": _rng.randf() * delta, "pan": _rng.randf_range(-0.6, 0.6)})
	elif rain_on and not cover and bool(ctx.get("shelter", false)):
		_next_drip -= delta
		if _next_drip <= 0.0:
			_next_drip = _rng.randf_range(0.15, 0.6)
			play("world.drip", {"k": 0.7, "pitch": 1.2, "pan": _rng.randf_range(-0.6, 0.6)})
	if an == "chalk" and _rng.randf() < delta * 3.0:
		play("world.chalkScratch")
	if an == "lamps" and _rng.randf() < delta * 1.2:
		play("world.lampFlicker", {"pan": _rng.randf_range(-0.8, 0.8)})
	if an == "rite" and _rng.randf() < delta * 0.4:
		play("world.chant")
	if an == "moth":
		var mk := clampf(float(ctx.get("moth_near", 0.0)), 0.0, 1.0)
		if _rng.randf() < delta * (5.0 + mk * 40.0):
			play("world.moth", {"k": 0.2 + mk, "pan": _rng.randf_range(-1.0, 1.0)})
		if mk > 0.6 and _rng.randf() < delta * 6.0:
			play("world.mothThump", {"k": 0.4 + mk * 0.6})
	# Distant stingers: one every 16–40 s (sooner when tense), a random kind and side, 40 % muffled.
	_next_stinger -= delta * (1.0 + tension * 1.5)
	if _next_stinger <= 0.0:
		_next_stinger = _rng.randf_range(16.0, 40.0)
		play(STINGERS[_rng.randi() % STINGERS.size()], {"pan": _rng.randf_range(-0.9, 0.9), "k": _rng.randf_range(0.75, 1.0), "lp": 0.4 if _rng.randf() < 0.4 else 1.0})
	if not out and not garage and night > 0.5:
		_next_indoor -= delta
		if _next_indoor <= 0.0:
			_next_indoor = _rng.randf_range(2.5, 7.0)
			play("world.drip", {"k": 0.35, "pitch": 1.3, "pan": _rng.randf_range(-0.9, 0.9)})
		if _rng.randf() < delta * 0.03:
			play("world.creak", {"pan": _rng.randf_range(-1.0, 1.0)})


## Footing (stepSurface): garage concrete, roof gravel, spiral stairs, tile indoors; outdoors the
## court, the track, grass on fields and gardens, otherwise the road.
static func surface(scene: String, on_spiral: bool, w: Vector2, out_objects: Array, sc: float) -> String:
	if scene != "out":
		if scene == "garage1":
			return "garage"
		if scene == "teach6":
			return "roof"
		return "stair" if on_spiral else "tile"
	var m := w / maxf(sc, 0.0001)
	var hit := "road"
	for o: Dictionary in out_objects:
		if not (m.x > float(o["x"]) and m.x < float(o["x"]) + float(o["w"]) and m.y > float(o["y"]) and m.y < float(o["y"]) + float(o["h"])):
			continue
		if o["k"] == "court":
			return "court"
		if o["k"] == "track":
			hit = "track"
		elif (o["k"] == "field" or o["k"] == "garden") and hit == "road":
			hit = "grass"
	return hit


# ---- interim: the first stage's cue names, mapped onto the bank until every call site is wired ----

const LEGACY := {"step": "step.tile", "step_heavy": "step.tile", "heart": "threat.heartLow", "thud": "foley.cupHit",
	"bell": "event.bell", "ding": "music.piano", "drip": "world.drip", "creak": "world.creak", "static": "dread.radio",
	"sting": "threat.sting", "scare": "threat.smileJump", "chime": "ui.achieve.epic", "engine": "scene.engine", "dismissal": "event.dismissal"}
var _legacy_loops: Dictionary = {}


func cue(id: String, db: float = 0.0, pitch: float = 1.0) -> void:
	play(String(LEGACY.get(id, id)), {"k": db_to_linear(db) * 3.0, "pitch": pitch})


func cue_at(id: String, pos: Vector3, db: float = 0.0) -> void:
	play(String(LEGACY.get(id, id)), {"pos": pos, "k": db_to_linear(db) * 3.0})


## A long one-shot (engine, dismissal bell) repeated while on.
func loop(id: String, on: bool, db: float = -12.0) -> void:
	if on and not _legacy_loops.has(id):
		_legacy_loops[id] = _t + 12.0
		play(String(LEGACY.get(id, id)))
	elif not on and _legacy_loops.has(id):
		_legacy_loops.erase(id)
		stop("scene" if id == "engine" else "event")


func looping(id: String) -> bool:
	return _legacy_loops.has(id) or bed_playing(id)


## Separate disposable voices for developer previews; no gameplay RNG or bed interruption.
func preview_play(id: String, opts: Dictionary = {}) -> bool:
	if not has(id) or not is_inside_tree(): return false
	var d: Dictionary=_index.sfx[id]
	var files: Array=d.files
	if files.is_empty(): return false
	var take: Dictionary=files[_audition_rng.randi()%files.size()]
	var vary: Dictionary=d.get("vary",{})
	var voice:=AudioStreamPlayer.new()
	voice.stream=_stream("sfx/"+String(take.file),false)
	voice.bus="Ui" if d.cat=="ui" else "Sfx"
	voice.volume_db=float(take.db)+linear_to_db(maxf(.001,float(opts.get("k",1))*(1+_audition_rng.randf_range(-1,1)*float(vary.get("g",0)))))
	voice.pitch_scale=maxf(.05,float(opts.get("pitch",1))*(1+_audition_rng.randf_range(-1,1)*float(vary.get("p",0))))
	voice.process_mode=Node.PROCESS_MODE_ALWAYS
	add_child(voice)
	_preview_voices.append(voice)
	voice.finished.connect(func() -> void:
		_preview_voices.erase(voice)
		voice.queue_free())
	voice.play()
	return true

func stop_preview() -> void:
	for voice in _preview_voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_preview_voices.clear()
