class_name LanPrediction
extends RefCounted
## Compare positions at the same simulated input tick, in the region's local frame.
const HISTORY_LIMIT := 180
const TOLERANCE := 0.012
const HARD_CORRECTION := 0.9
var history: Dictionary = {}
var corrections := 0
var error_metres := 0.0
var _applied := Vector3.ZERO
var _remaining := Vector3.ZERO
var _latest_ack := -1
var _expired_through := -1
var _obstructed_acks := 0


func record(sequence: int, position: Vector3) -> void:
	history[sequence] = position - _applied
	while history.size() > HISTORY_LIMIT:
		_expired_through = history.keys().front()
		history.erase(_expired_through)


func reconcile(body: CharacterBody3D, authority: Vector3, ack: int, predict: bool) -> void:
	if ack < _latest_ack: return
	if not predict:
		# A seat, locker, fall or scripted interaction owns the body's exact pose.
		clear()
		_latest_ack = ack
		body.position = authority
		return
	if ack == _latest_ack: return
	_latest_ack = ack
	if not history.has(ack):
		if ack >= 0 and ack <= _expired_through: _anchor(body, authority, ack)
		return
	var offset: Vector3 = authority - (history[ack] + _applied)
	for key: int in history.keys():
		if key > ack: break
		history.erase(key)
	error_metres = offset.length()
	if error_metres < TOLERANCE:
		_remaining = Vector3.ZERO
		_obstructed_acks = 0
	elif error_metres >= HARD_CORRECTION or (_obstructed_acks >= 5 and error_metres > .12):
		_anchor(body, authority, ack)
	else:
		_remaining = offset
		if error_metres > 0.08: corrections += 1


func _anchor(body: CharacterBody3D, authority: Vector3, ack: int) -> void:
	clear()
	_latest_ack = ack
	body.position = authority
	body.velocity = Vector3.ZERO
	body.reset_physics_interpolation()
	corrections += 1


func advance(body: CharacterBody3D, dt: float, travelled: Vector3 = Vector3.ZERO) -> void:
	if _remaining.is_zero_approx(): return
	var before := body.position
	var portion := _remaining * (1.0 - exp(-12.0 * dt))
	if _remaining.length_squared() < 0.000004: portion = _remaining
	# A late acknowledgement can shorten a real stride. It must not reverse it.
	# Use actual post-collision travel, including analog input and rotated regions.
	var stride := Vector3(travelled.x, 0, travelled.z)
	var distance := stride.length()
	if distance > .0001:
		var along := stride / distance
		var opposing := -portion.dot(along)
		if opposing > distance * .8: portion += along * (opposing - distance * .8)
	var motion := body.get_parent_node_3d().global_basis * portion
	var hit := body.move_and_collide(motion)
	var applied := body.position - before
	_applied += applied
	_remaining -= applied
	if hit != null:
		# A wall can block one component while the tangential correction is valid.
		var normal := body.get_parent_node_3d().global_basis.inverse() * hit.get_normal()
		normal = normal.normalized()
		if _remaining.dot(normal) < -.12: _obstructed_acks += 1
		_remaining = _remaining.slide(normal)
	elif _remaining.length_squared() < TOLERANCE * TOLERANCE:
		_obstructed_acks = 0


func rebase(frame: Transform3D) -> void:
	for sequence: int in history: history[sequence] = frame * (history[sequence] as Vector3)
	_applied = frame.basis * _applied
	_remaining = frame.basis * _remaining


func clear() -> void:
	history.clear()
	_remaining = Vector3.ZERO
	_applied = Vector3.ZERO
	_latest_ack = -1
	_expired_through = -1
	_obstructed_acks = 0
