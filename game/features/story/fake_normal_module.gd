class_name FakeNormalModule
extends FeatureModule
## Visual state only. Old saves may contain a second-day draw or a laugh meter.
## Neither starts the ending when loading a game.
var showing := false


func module_id() -> StringName:
	return &"story.fake_normal"


func reset() -> void:
	showing = false


func capture() -> Dictionary:
	return {}


func validate(_data: Dictionary) -> String:
	return ""


func restore(_data: Dictionary) -> void:
	reset()


func active() -> bool:
	return showing
