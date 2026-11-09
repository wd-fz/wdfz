class_name KeyBindings
extends RefCounted
## Rebindable keyboard actions: two physical keys per action. Pure data — persisted in settings.json by
## GameSettings and pushed into the InputMap by GameSettings.apply_bindings(). Pause stays on Esc and is not
## listed (every menu also closes on Esc, so it can never be lost).

## [action, label, group, default keys (physical keycodes)]
const ACTIONS := [
	["move_forward", "前进", "移动", [KEY_W, KEY_UP]],
	["move_back", "后退", "移动", [KEY_S, KEY_DOWN]],
	["move_left", "左移", "移动", [KEY_A, KEY_LEFT]],
	["move_right", "右移", "移动", [KEY_D, KEY_RIGHT]],
	["sprint", "奔跑（按住）", "移动", [KEY_SHIFT, 0]],
	["interact", "交互", "动作", [KEY_E, 0]],
	["torch", "手电", "动作", [KEY_F, 0]],
	["bag", "背包", "动作", [KEY_TAB, 0]],
	["hot_1", "快捷栏 1", "动作", [KEY_1, 0]],
	["hot_2", "快捷栏 2", "动作", [KEY_2, 0]],
	["lift_close", "电梯关门", "动作", [KEY_V, 0]],
	["lesson", "上课 / 课程", "校园", [KEY_R, 0]],
	["notes", "调查笔记", "校园", [KEY_N, 0]],
	["think", "想一想", "校园", [KEY_H, 0]],
	["mute", "静音", "其他", [KEY_M, 0]],
]
## Keys that can never be bound: menus, system and pointer-capture keys.
const RESERVED := [KEY_ESCAPE, KEY_F2, KEY_F9, KEY_ENTER, KEY_KP_ENTER, KEY_META]


## A short readable name for a physical key.
static func key_name(key: int) -> String:
	var special := {KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_SHIFT: "Shift", KEY_CTRL: "Ctrl", KEY_ALT: "Alt",
		KEY_SPACE: "空格", KEY_TAB: "Tab", KEY_BACKSPACE: "退格", KEY_CAPSLOCK: "Caps"}
	if special.has(key):
		return String(special[key])
	return OS.get_keycode_string(key as Key)


static func ids() -> Array:
	var out: Array = []
	for a: Array in ACTIONS:
		out.append(a[0])
	return out


static func label(action: String) -> String:
	for a: Array in ACTIONS:
		if a[0] == action:
			return String(a[1])
	return action


static func defaults() -> Dictionary:
	var out := {}
	for a: Array in ACTIONS:
		out[a[0]] = (a[3] as Array).duplicate()
	return out


## Every action gets exactly two slots; unknown actions, reserved keys and duplicates are dropped
## (a duplicate keeps its first place in ACTIONS order).
static func normalize(raw: Variant) -> Dictionary:
	var out := defaults()
	if not raw is Dictionary:
		return out
	var used := {}
	for a: Array in ACTIONS:
		var id := String(a[0])
		var keys: Variant = (raw as Dictionary).get(id)
		if not keys is Array:
			for k: int in out[id]:
				if k != 0: used[k] = true
			continue
		var slots: Array = [0, 0]
		for i in mini(2, (keys as Array).size()):
			var v: Variant = keys[i]
			if not (v is int or v is float):
				continue
			var k := int(v)
			if k <= 0 or RESERVED.has(k) or used.has(k):
				continue
			slots[i] = k
			used[k] = true
		out[id] = slots
	# A default that was taken by another action stays free; an action with no key at all gets its default back if free.
	for a: Array in ACTIONS:
		var id := String(a[0])
		var slots: Array = out[id]
		if int(slots[0]) == 0 and int(slots[1]) == 0:
			var d := int(a[3][0])
			if not used.has(d):
				slots[0] = d
				used[d] = true
	return out


## Which action and slot hold this key, or ["", -1].
static func holder(bindings: Dictionary, key: int) -> Array:
	for id: String in bindings:
		var slots: Array = bindings[id]
		for i in slots.size():
			if int(slots[i]) == key:
				return [id, i]
	return ["", -1]


## Put key on (action, slot). When another action already has it, the two swap (the other gets this slot's old key).
## Returns {"ok": bool, "swapped": action or "", "why": reason}.
static func assign(bindings: Dictionary, action: String, slot: int, key: int) -> Dictionary:
	if not bindings.has(action) or slot < 0 or slot > 1:
		return {"ok": false, "swapped": "", "why": "没有这个动作"}
	if RESERVED.has(key):
		return {"ok": false, "swapped": "", "why": "这个键留给菜单与系统，不能使用"}
	var slots: Array = bindings[action]
	var old := int(slots[slot])
	if old == key:
		return {"ok": true, "swapped": "", "why": ""}
	var h := holder(bindings, key)
	var swapped := ""
	if String(h[0]) != "":
		var other: Array = bindings[h[0]]
		other[int(h[1])] = old
		swapped = String(h[0])
	slots[slot] = key
	return {"ok": true, "swapped": swapped, "why": ""}


## Clear a slot (0 means unbound). The first slot of an action is kept if it is the only key left.
static func clear(bindings: Dictionary, action: String, slot: int) -> bool:
	if not bindings.has(action):
		return false
	var slots: Array = bindings[action]
	if int(slots[1 - slot]) == 0:
		return false
	slots[slot] = 0
	return true


static func reset(bindings: Dictionary, action: String) -> void:
	var d := defaults()
	if action == "":
		for id: String in d:
			bindings[id] = d[id]
		return
	# Another action holding one of the defaults gets this action's old key in that slot instead.
	var spare: Array = []
	for k: int in bindings[action]:
		if k != 0 and not (d[action] as Array).has(k):
			spare.append(k)
	for k: int in d[action]:
		if k == 0: continue
		var h := holder(bindings, k)
		if String(h[0]) != "" and String(h[0]) != action:
			(bindings[h[0]] as Array)[int(h[1])] = spare.pop_front() if not spare.is_empty() else 0
	bindings[action] = d[action]
