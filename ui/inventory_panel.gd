class_name InventoryPanel
extends Control

signal close_requested
signal drop_requested(id: String)

var _inventory: InventoryModule
var _investigation: InvestigationModule
var _slots: Array[Button] = []


func _ready() -> void:
	%Close.pressed.connect(func() -> void: close_requested.emit())
	%Drop.pressed.connect(func() -> void:
		if _inventory != null:
			drop_requested.emit(_inventory.selected_id()))
	%Quick1.pressed.connect(func() -> void: _set_quick(0))
	%Quick2.pressed.connect(func() -> void: _set_quick(1))
	for index in InventoryModule.CAPACITY:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(func() -> void:
			if _inventory != null:
				_inventory.select(index))
		%Slots.add_child(button)
		_slots.append(button)


func present(inventory: InventoryModule, investigation: InvestigationModule) -> void:
	_inventory = inventory
	_investigation = investigation
	%Status.text = "背包和记录已打开，世界暂停。"
	refresh()
	%Close.grab_focus()


func clear() -> void:
	_inventory = null
	_investigation = null


func refresh() -> void:
	if _inventory == null:
		return
	var items := _inventory.items()
	%Capacity.text = "随身物品 %d / %d" % [items.size(), InventoryModule.CAPACITY]
	for index in _slots.size():
		var held := index < items.size()
		_slots[index].text = "%d · %s" % [index + 1, _inventory.details(items[index])["name"] if held else "空位"]
		_slots[index].disabled = not held
		_slots[index].set_pressed_no_signal(index == _inventory.selected_index() and held)
	var selected := _inventory.selected_id()
	var detail := _inventory.details(selected)
	%Description.text = "%s\n%s" % [detail["name"], detail["description"]] if not detail.is_empty() else "选择一件物品，可以查看、放入快捷栏或放到脚边。"
	%Drop.disabled = selected.is_empty()
	var quick := _inventory.quick_slots()
	for index in 2:
		var button: Button = %Quick1 if index == 0 else %Quick2
		button.text = "快捷 %d：%s" % [index + 1, _inventory.details(quick[index]).get("name", "空")]
		button.disabled = selected.is_empty() and String(quick[index]).is_empty()
	if _investigation != null:
		%Objective.text = _investigation.objective()
		var paragraphs := PackedStringArray()
		for note: Dictionary in _investigation.notes():
			paragraphs.append(note["title"] + "\n" + note["text"])
		%Notes.text = "\n\n".join(paragraphs) if not paragraphs.is_empty() else "还没有调查记录。查看课桌、讲台或门锁后，记录会留在这里。"


func _set_quick(index: int) -> void:
	if _inventory == null:
		return
	var selected := _inventory.selected_id()
	_inventory.set_quick(index, "" if _inventory.quick_slots()[index] == selected else selected)


func show_status(text: String) -> void:
	%Status.text = text
