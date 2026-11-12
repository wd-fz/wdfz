class_name LanPrediction
extends RefCounted
## Bounded replay of unacknowledged local inputs against the same world collision.
var history: Array = []
var corrections := 0
var error_metres := 0.0


func record(sequence: int, axis: Vector2, yaw: float, running: bool, multiplier: float, dt: float) -> void:
	history.append({"seq": sequence, "axis": axis, "yaw": yaw, "running": running, "multiplier": multiplier, "dt": dt})
	while history.size() > 30: history.pop_front()


func reconcile(body: CharacterBody3D, authority: Vector3, ack: int, enabled: bool) -> void:
	while not history.is_empty() and int(history[0]["seq"]) <= ack: history.pop_front()
	var before := body.position
	body.position = authority
	var replayed := 0.0
	if enabled:
		for frame: Dictionary in history:
			var dt := minf(float(frame["dt"]), 1.0 / 30.0)
			if replayed + dt > 0.25: break
			replayed += dt
			var direction: Vector3 = Basis(Vector3.UP, float(frame["yaw"])) * Vector3(frame["axis"].x, 0, frame["axis"].y)
			var displacement := direction * (CharacterMotor.RUN if frame["running"] else CharacterMotor.WALK) * float(frame["multiplier"]) * dt
			for _slide in 3:
				var collision := body.move_and_collide(displacement)
				if collision == null: break
				displacement = collision.get_remainder().slide(collision.get_normal())
				if displacement.length_squared() < 0.000001: break
	error_metres = body.position.distance_to(before)
	if error_metres > 0.08: corrections += 1


func clear() -> void:
	history.clear()
