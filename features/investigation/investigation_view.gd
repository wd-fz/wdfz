class_name InvestigationView
extends Node3D

var _inventory: InventoryModule
var _rules: InvestigationModule


func bind_rules(inventory: InventoryModule, rules: InvestigationModule) -> void:
	_unbind()
	_inventory = inventory
	_rules = rules
	_inventory.changed.connect(_refresh)
	_rules.changed.connect(_refresh)
	%DoorControl.rules = rules
	%DoorControl.clearance = %DoorClearance
	_refresh()


func _refresh() -> void:
	%CabinetKey.visible = _rules.key_available()
	%Cabinet.prompt = "拿取机房钥匙" if _rules.key_available() else "查看空抽屉"
	%DoorLeaf.visible = not _rules.door_open()
	%DoorCollision.set_deferred("disabled", _rules.door_open())
	%DoorControl.prompt = "关闭机房门" if _rules.door_open() else "打开机房门"
	%DoorLabel.text = "机房 · 门已打开" if _rules.door_open() else "机房 · 需要铜钥匙"


func _unbind() -> void:
	if _inventory != null and _inventory.changed.is_connected(_refresh):
		_inventory.changed.disconnect(_refresh)
	if _rules != null and _rules.changed.is_connected(_refresh):
		_rules.changed.disconnect(_refresh)
	_inventory = null
	_rules = null


func _exit_tree() -> void:
	_unbind()
