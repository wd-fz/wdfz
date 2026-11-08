class_name CameraMotion
extends RefCounted
## Old engine/scene.js camera motion. Presentation state is independent of the saved look
## direction and the body, so sitting, shaking and injury never accumulate in a save pose.

const EYE := 1.65
const SEATED_EYE := 1.12
const FOV := 72.0

var eye_height := EYE
var fov := FOV
var phase := 0.0
var shake_enabled := true


func reset(seated: bool = false) -> void:
	eye_height = SEATED_EYE if seated else EYE
	fov = FOV
	phase = 0.0


func advance(dt: float, seated: bool, moving: bool, running: bool, drop: float, aspect: float, shake: float = 0.0) -> Dictionary:
	dt = maxf(0.0, dt)
	var bob := 0.0
	if moving and not seated:
		phase += dt * (13.5 if running else 8.5)
		if shake_enabled:
			bob = sin(phase) * (0.052 if running else 0.030)
	eye_height = lerpf(eye_height, SEATED_EYE if seated else EYE, minf(1.0, dt * 9.0))
	fov = lerpf(fov, FOV + (9.0 if running and moving else 0.0), minf(1.0, dt * 8.0))
	var jitter := randf_range(-0.03, 0.03) * clampf(shake, 0.0, 1.0) if shake_enabled and shake > 0.0 and dt > 0.0 else 0.0
	# The near plane's corners must remain inside the player's collision circle,
	# including on ultrawide displays. Keep vertical FOV, as in the Web camera.
	var tangent := tan(deg_to_rad(fov) * 0.5)
	var near := minf(0.08, (CampusGeometry.PRAD * CampusGeometry.U2M) / (1.3 * sqrt(1.0 + tangent * tangent * (1.0 + aspect * aspect))))
	return {"height": eye_height + bob + jitter - drop, "pitch": -0.06 if seated else 0.0, "fov": fov, "near": near}
