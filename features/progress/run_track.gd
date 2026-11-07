class_name RunTrack
extends RefCounted
## Replay track encoding (domain/run-track.js): samples [t (tenths of a second), scene index, x/2, y/2,
## heading 0–63], difference per field, zig-zag, 5 bits per character; the alphabet is the floor sketch's
## (A–Z a–z 0–9 - _). A 30-minute run is about 15–20 KB.

const B := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const FIELDS := 5


static func _zig(n: int) -> int:
	return n * 2 if n >= 0 else -n * 2 - 1


static func _unzig(z: int) -> int:
	return (z >> 1) if z % 2 == 0 else -((z + 1) >> 1)


static func _put(out: PackedStringArray, v: int) -> void:
	var z := _zig(v)
	while z >= 32:
		out.append(B.substr((z % 32) | 32, 1))
		z = z >> 5
	out.append(B.substr(z, 1))


static func encode(samples: Array) -> String:
	var out := PackedStringArray()
	var prev := [0, 0, 0, 0, 0]
	for p: Array in samples:
		for k in FIELDS:
			var v := roundi(float(p[k]))
			_put(out, v - int(prev[k]))
			prev[k] = v
	return "".join(out)


## Bad data stops the decode there; what came before is still used.
static func decode(text: String) -> Array:
	var res: Array = []
	var prev := [0, 0, 0, 0, 0]
	var cur: Array = []
	var k := 0
	var v := 0
	var mul := 1
	for i in text.length():
		var c := B.find(text.substr(i, 1))
		if c < 0:
			return res
		v += (c & 31) * mul
		if (c & 32) != 0:
			mul *= 32
			continue
		prev[k] = int(prev[k]) + _unzig(v)
		cur.append(prev[k])
		v = 0
		mul = 1
		k += 1
		if k == FIELDS:
			res.append(cur)
			cur = []
			k = 0
	return res


## The position at time t: linear between the two surrounding samples (not across a change of scene).
static func at(samples: Array, t: float) -> Array:
	if samples.is_empty():
		return []
	var lo := 0
	var hi := samples.size() - 1
	if t <= float(samples[0][0]):
		return (samples[0] as Array).duplicate()
	if t >= float(samples[hi][0]):
		return (samples[hi] as Array).duplicate()
	while hi - lo > 1:
		var m := (lo + hi) >> 1
		if float(samples[m][0]) <= t:
			lo = m
		else:
			hi = m
	var a: Array = samples[lo]
	var b: Array = samples[hi]
	if a[1] != b[1] or b[0] == a[0]:
		return a.duplicate()
	var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
	return [t, a[1], float(a[2]) + (float(b[2]) - float(a[2])) * u, float(a[3]) + (float(b[3]) - float(a[3])) * u, a[4]]
