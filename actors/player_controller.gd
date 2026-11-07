class_name PlayerController
extends CharacterBody3D

signal interaction_requested(id: StringName)
## E pressed with no physical interactable in front: tile-based rules (campus) decide.
signal free_interaction_requested
signal focus_changed(prompt: String)

## Web version input.js SPD_WALK = 21 and SPD_RUN = 36.4 world units/s; 1 unit = 1/9 m.
@export var walk_speed := 21.0 / 9.0
@export var sprint_speed := 36.4 / 9.0
@export var mouse_sensitivity := 0.0025
@export var touch_sensitivity := 0.004

@onready var camera: Camera3D = %Camera
@onready var ray: RayCast3D = %InteractionRay

var enabled := false
## Seated (old S.seated): the body stays on the chair, the view still turns.
var seated := false
## Sprint allowed by the stamina rules (input.js tired / STAM_BACK).
var can_sprint := true
var moving := false
var sprinting := false
## Snack (items.js): walking and running ×1.5 for 30 s.
var speed_multiplier := 1.0
var _touch_move := Vector2.ZERO
var _touch_sprint := false
var _focus: WorldInteractable
var _prompt := ""


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	# Godot synthesizes device -1 mouse events for Control button taps.
	# Keep those for UI, but never capture/rotate the world camera with them.
	if event is InputEventMouse and event.device == -1:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.screen_relative * mouse_sensitivity)
	elif event.is_action_pressed("interact") and not event.is_echo():
		request_interaction()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if seated:
		# The seated body overlaps its chair (old S.seated skips moveBy entirely).
		velocity = Vector3.ZERO
		moving = false
		sprinting = false
		_update_focus()
		return
	var direction := (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + _touch_move).limit_length()
	var world_direction := global_basis * Vector3(direction.x, 0.0, direction.y)
	var want_run := (Input.is_action_pressed("sprint") or _touch_sprint or _touch_move.length() > 0.96) and direction.length() > 0.08
	sprinting = want_run and can_sprint
	var speed := (sprint_speed if sprinting else walk_speed) * speed_multiplier
	velocity.x = world_direction.x * speed
	velocity.z = world_direction.z * speed
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var before := global_position
	move_and_slide()
	moving = Vector2(global_position.x - before.x, global_position.z - before.z).length() > 0.0001 / 9.0
	if not moving:
		sprinting = false
	_update_focus()


## Movement input this frame (old updatePlayer: a seated player stands up when it exceeds 0.08).
func wants_move() -> bool:
	if not enabled:
		return false
	return (Input.get_vector("move_left", "move_right", "move_forward", "move_back") + _touch_move).length() > 0.08


func _update_focus() -> void:
	ray.force_raycast_update()
	var collider: Object = ray.get_collider()
	_focus = collider as WorldInteractable
	var next_prompt := _focus.prompt if is_instance_valid(_focus) else ""
	if next_prompt != _prompt:
		_prompt = next_prompt
		focus_changed.emit(_prompt)


func request_interaction() -> void:
	if not enabled:
		return
	_update_focus() # Never use a target cached before a teleport/pause.
	if is_instance_valid(_focus) and not _focus.interaction_id.is_empty():
		interaction_requested.emit(_focus.interaction_id)
	else:
		free_interaction_requested.emit()


func set_touch_move(value: Vector2) -> void:
	_touch_move = value.limit_length() if enabled else Vector2.ZERO


func set_touch_sprint(value: bool) -> void:
	_touch_sprint = value and enabled


func look_from_touch(relative: Vector2) -> void:
	if enabled:
		apply_look(relative * touch_sensitivity)


func apply_look(delta: Vector2) -> void:
	rotation.y = wrapf(rotation.y - delta.x, -PI, PI)
	camera.rotation.x = clampf(camera.rotation.x - delta.y, -1.4, 1.4)


func clear_input() -> void:
	_touch_move = Vector2.ZERO
	_touch_sprint = false
	velocity = Vector3.ZERO
	_focus = null
	_prompt = ""
	focus_changed.emit("")


func capture_pose() -> Dictionary:
	return {
		"position": [position.x, position.y, position.z],
		"yaw": wrapf(rotation.y, -PI, PI),
		"pitch": camera.rotation.x,
	}


## Seamless move (campus door thresholds): keep held input and velocity direction.
func place(data: Dictionary) -> void:
	var coordinates: Array = data["position"]
	position = Vector3(coordinates[0], coordinates[1], coordinates[2])
	rotation = Vector3(0.0, float(data["yaw"]), 0.0)
	camera.rotation = Vector3(float(data["pitch"]), 0.0, 0.0)
	reset_physics_interpolation()


func has_focus() -> bool:
	return is_instance_valid(_focus)


func restore_pose(data: Dictionary) -> void:
	clear_input()
	var coordinates: Array = data["position"]
	position = Vector3(coordinates[0], coordinates[1], coordinates[2])
	rotation = Vector3(0.0, float(data["yaw"]), 0.0)
	camera.rotation = Vector3(float(data["pitch"]), 0.0, 0.0)
	reset_physics_interpolation()
