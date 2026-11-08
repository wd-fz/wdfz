class_name WorldInteractable
extends StaticBody3D
## Presentation-side target. Rules receive the stable ID, not this Node.

@export var interaction_id: StringName
@export var prompt := "查看"


func blocked_reason(_player: CharacterBody3D) -> String:
	return ""
