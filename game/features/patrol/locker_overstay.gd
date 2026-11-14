class_name LockerOverstay
extends RefCounted
## A safe place that does not stay safe forever, with warning and a way out (2026-11-14 horror plan, item 7,
## user-approved; docs/plan/中式与西式恐怖及吓人手法.md). The locker hides you from the patroller as before.
## But staying in one while nothing is hunting you is noticed by the locker itself:
##   45 s  two knocks on the metal, from the inside;
##   55 s  someone else's breath in the locker with you;
##   65 s  a breath on the neck: SAN −4 and the player stumbles out.
## The clock only runs while there is no threat (no chase, the patroller not hunting this locker and not
## within hearing): it never pushes the player out into danger, and hiding when it is needed is untouched.
## Leaving resets it. Single player only (the cooperative mode keeps its own hiding rules).

const KNOCK := 45.0
const BREATH := 55.0
const PUSH := 65.0
const SAN_COST := 4.0

var t := 0.0
var stage := 0


func reset() -> void:
	t = 0.0
	stage = 0


## Returns "" or the beat that happens now: "knock", "breath", "push".
func tick(dt: float, hiding: bool, threat: bool) -> String:
	if not hiding:
		reset()
		return ""
	if threat or not (dt > 0.0):
		return ""
	t += dt
	if stage == 0 and t >= KNOCK:
		stage = 1
		return "knock"
	if stage == 1 and t >= BREATH:
		stage = 2
		return "breath"
	if stage == 2 and t >= PUSH:
		stage = 3
		return "push"
	return ""
