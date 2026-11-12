class_name CharacterMotor
extends RefCounted
## Identical movement math for local input and authoritative remote input.
const WALK := 21.0 / 9.0
const RUN := 36.4 / 9.0


static func advance(body: CharacterBody3D, axis: Vector2, yaw: float, run: bool, multiplier: float, dt: float, gravity: float = 9.8, max_fall: float = INF, walk_speed: float = WALK, run_speed: float = RUN) -> void:
	var direction := Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y).limit_length()
	var speed := (run_speed if run else walk_speed) * multiplier
	body.velocity.x = direction.x * speed
	body.velocity.z = direction.z * speed
	if body.is_on_floor(): body.velocity.y = 0.0
	else: body.velocity.y = maxf(-max_fall, body.velocity.y - gravity * dt)
	body.move_and_slide()
