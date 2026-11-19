class_name FigureGait
extends RefCounted
## Sample locomotion by distance, so stopping or teleporting never runs a walk cycle.
const DIRECTORY := "res://assets/campus/figures/motion/%s.glb"


static func attach(root: Node3D) -> void:
	var animation := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation == null: return
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.set_meta(&"gait_player", animation)


static func step(root: Node3D, distance: float, dt: float) -> void:
	if not root.has_meta(&"gait_player"): return
	var animation: AnimationPlayer = root.get_meta(&"gait_player")
	var moving := distance > .0001 and distance < 1.5
	if moving:
		if animation.current_animation != "walk":
			animation.play("walk", .14)
		animation.advance(distance / 1.25)
	elif animation.current_animation == "walk":
		animation.play("idle", .16)
		animation.advance(dt)
	elif animation.current_animation == "idle" and animation.current_animation_position < .20:
		animation.advance(dt)
