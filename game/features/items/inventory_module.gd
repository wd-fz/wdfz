class_name InventoryModule
extends FeatureModule
## Bag, hot slots, container search and item use, ported from the Web version (reference
## wd-fz.github.io@0bf508a): domain/inventory.js (InventoryRules), items.js (ITEMS, ITEM_USE,
## ITEM_READ, toggleTorch, pill / snack timers) and interact.js (searchContainer, doSearch,
## searchLoot, DESK_LOOT, LAB_LOOT, podium chalk).
##
## Item uses that need unported systems (phone, leave slip, compass, coin, atlas, map, memo,
## umbrella shield, portal materials) answer honestly that they are not ported yet.

const STATE_VERSION := 1
const SEARCH_SECONDS := 0.8
const SEARCH_REACH := 5.0
const ITEM_READ := ["card", "notebook", "hw", "usb", "key", "roomkey", "metronome", "goggles", "coat", "battery", "chalk", "pen"]
const NOT_PORTED: Array = []
const EMPTY_LINES := ["我：空的。只有一层灰。", "我：空的。抽屉底下用圆珠笔写着一个名字，被涂黑了。", "我：空的。最里面有一小撮头发。"]

var _rooms: Dictionary = {}
var _campus: Dictionary = {}
var bag: Array = []
var hot: Array = [null, null]
var torch_on := false
var brolly_up := false          # the umbrella is open (USE.brollyShield): not saved, a new run starts closed
var pill_t := 0.0
var snack_t := 0.0
var desk_used: Dictionary = {}
var pending_loot: Dictionary = {}
var key_miss := 0
var hw_taken := false
var _job: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _notices: PackedStringArray = []


func _init(rooms: Dictionary = {}, campus: Dictionary = {}) -> void:
	_rooms = rooms
	_campus = campus


func module_id() -> StringName:
	return &"items.bag"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	bag = []
	hot = [null, null]
	torch_on = false
	brolly_up = false
	pill_t = 0.0
	snack_t = 0.0
	desk_used = {}
	pending_loot = {}
	key_miss = 0
	hw_taken = false
	_job = {}
	_rng.randomize()
	_notices = PackedStringArray()


func set_seed(value: int) -> void:
	_rng.seed = value


func capture() -> Dictionary:
	return {"bag": bag.duplicate(), "hot": hot.duplicate(), "torch": torch_on, "pill_t": pill_t, "snack_t": snack_t,
		"desk_used": desk_used.duplicate(), "pending_loot": pending_loot.duplicate(), "key_miss": key_miss,
		"hw_taken": hw_taken, "rng_seed": str(_rng.seed), "rng_state": str(_rng.state)}


func validate(data: Dictionary) -> String:
	var items: Dictionary = _items()
	var b: Variant = data.get("bag")
	if not b is Array or b.size() > capacity():
		return "背包无效"
	for id: Variant in b:
		if not id is String or not items.has(id):
			return "背包里有未知物品：%s" % id
	var h: Variant = data.get("hot")
	if not h is Array or h.size() != 2:
		return "快捷栏无效"
	for id: Variant in h:
		if id != null and not (id is String and (b as Array).has(id)):
			return "快捷栏引用了背包外的物品"
	if not SaveSchema.number_in(data.get("pill_t"), 0, 1000) or not SaveSchema.number_in(data.get("snack_t"), 0, 1000):
		return "物品计时无效"
	if not data.get("desk_used") is Dictionary or not data.get("pending_loot") is Dictionary:
		return "翻找记录无效"
	if not String(data.get("rng_state", "")).is_valid_int():
		return "物品随机状态无效"
	return ""


func restore(data: Dictionary) -> void:
	bag = data["bag"].duplicate()
	hot = data["hot"].duplicate()
	torch_on = bool(data.get("torch", false)) and bag.has("torch")
	pill_t = float(data["pill_t"])
	snack_t = float(data["snack_t"])
	desk_used = data["desk_used"].duplicate()
	pending_loot = data["pending_loot"].duplicate()
	key_miss = int(data.get("key_miss", 0))
	hw_taken = bool(data.get("hw_taken", false))
	_rng.seed = int(String(data.get("rng_seed", "0")))
	_rng.state = int(String(data["rng_state"]))
	_job = {}


func take_notices() -> PackedStringArray:
	var out := _notices
	_notices = PackedStringArray()
	return out


func _say(text: String) -> void:
	_notices.append(text)


func _items() -> Dictionary:
	return _campus.get("items", {})


func capacity() -> int:
	return int(_campus.get("bag_capacity", 8))


func item_name(id: String) -> String:
	return String(_items().get(id, {}).get("n", id))


func item_text(id: String) -> String:
	return String(_items().get(id, {}).get("d", ""))


func has(id: String) -> bool:
	return bag.has(id)


## InventoryRules.add + items.js inventoryAdd messages.
func add(id: String) -> bool:
	if id.is_empty() or not _items().has(id) or has(id):
		return false
	if bag.size() >= capacity():
		_say("我：装不下了。")
		return false
	bag.append(id)
	_say("我：拿到了「%s」。" % item_name(id))
	return true


func remove(id: String) -> bool:
	var i := bag.find(id)
	if i < 0:
		return false
	bag.remove_at(i)
	for k in 2:
		if hot[k] == id:
			hot[k] = null
	if id == "torch":
		torch_on = false
	if id == "brolly":
		brolly_up = false
	return true


## items.js dropSelected: the item is put down (gone). The unique portal materials can be taken again
## from where they were found, so a wrong drop cannot cut a route (the app clears the facility flag).
func drop(id: String) -> bool:
	if not remove(id):
		return false
	_say("我：我把「%s」放下了。" % item_name(id))
	return true


func set_hot(index: int, id: Variant) -> bool:
	if index < 0 or index > 1 or (id != null and not has(String(id))):
		return false
	hot[index] = id
	return true


## Watch item or talent (Talent.capability('clock')); talents are not ported.
func has_clock() -> bool:
	return has("watch")


func snack_active() -> bool:
	return snack_t > 0.0


## items.js inventoryUse.
func use(id: String, tsec: float) -> Dictionary:
	if not has(id):
		return {}
	var nm := item_name(id)
	match id:
		"torch":
			torch_on = not torch_on
			return {"toast": "手电：开" if torch_on else "手电：关"}
		"brolly":
			brolly_up = not brolly_up
			return {"toast": "撑开伞" if brolly_up else "收起伞"}
		"pill":
			pill_t = float(_campus.get("pill", {}).get("sec", 30))
			remove("pill")
			return {"notice": "我：药片很苦。手慢慢不抖了。", "toast": "药片咽下去了 · 作用持续 %d 秒" % int(pill_t)}
		"snack":
			snack_t = float(_campus.get("stamina", {}).get("snack_sec", 30))
			remove("snack")
			return {"notice": "我：甜的。腿一下子轻了。", "toast": "士力架 · %d 秒内移速 ×1.5，疾跑不耗体力" % int(snack_t)}
		"watch":
			return {"notice": "我：现在是 %s。" % SchoolClock.fmt_clock(tsec), "toast": "现在是 " + SchoolClock.fmt_clock(tsec)}
		"elixir":
			return {"notice": "我：留着。没有说明书，可我知道它什么时候该吃——到时候它自己会起作用。"}
		"seal":
			return {"notice": "我：符纸在口袋里很安静。等那个高个子盯上我的时候，它才会动。"}
		"key":
			return {"car_key": true}
		"leave":
			return {"leave": true}
		"phone":
			return {"phone": true}
		"medkit":
			return {"medkit": true}
		"chalk":
			return {"chalk": true}
		"compass", "atlas", "map", "memo", "coil", "lens", "vial":
			return {"facility_item": id}
		"coin":
			return {"coin": true}
	if id in ITEM_READ:
		return {"notice": "我：%s。%s" % [nm, item_text(id)]}
	if id in NOT_PORTED:
		return {"notice": "（Godot 版尚未移植「%s」的用法）" % nm}
	return {"notice": "我：%s。%s" % [nm, item_text(id)]}


func use_hot(index: int, tsec: float) -> Dictionary:
	var id: Variant = hot[index] if index >= 0 and index < 2 else null
	if id == null:
		return {"toast": "快捷栏 %d 是空的 —— 打开背包，选中物品后点「放到快捷栏 %d」" % [index + 1, index + 1]}
	if not has(String(id)):
		hot[index] = null
		return {"toast": "「%s」已经不在了" % item_name(String(id))}
	return use(String(id), tsec)


## Per-step timers: pill restores SAN (handled by the caller), snack wears off.
func step(dt: float) -> float:
	var san_gain := 0.0
	if pill_t > 0.0:
		var pd := minf(dt, pill_t)
		san_gain = float(_campus.get("pill", {}).get("rate", 2)) * pd
		pill_t -= pd
	if snack_t > 0.0:
		snack_t = maxf(0.0, snack_t - dt)
	return san_gain


# ---- searching (interact.js searchContainer / searchTick / doSearch) ----

func searching() -> bool:
	return not _job.is_empty()


func search_progress() -> float:
	return 0.0 if _job.is_empty() else clampf(float(_job["t"]) / SEARCH_SECONDS, 0.0, 1.0)


func start_search(room_id: String, c: int, r: int, me: Vector2) -> void:
	var key := "%s:%d:%d" % [room_id, c, r]
	if desk_used.has(key):
		_say("我：翻过了。")
		return
	if _job.is_empty():
		_job = {"room": room_id, "c": c, "r": r, "x": me.x, "y": me.y, "t": 0.0}


## Hold still for 0.8 s; walking away (5 units) or leaving the room cancels.
func search_tick(dt: float, room_id: String, me: Vector2) -> void:
	if _job.is_empty():
		return
	if room_id != _job["room"] or me.distance_to(Vector2(_job["x"], _job["y"])) > SEARCH_REACH:
		_job = {}
		_say("我：手一松，没翻完。")
		return
	_job["t"] = float(_job["t"]) + dt
	if float(_job["t"]) >= SEARCH_SECONDS:
		var j := _job
		_job = {}
		do_search(String(j["room"]), int(j["c"]), int(j["r"]))


func cancel_search() -> void:
	_job = {}


func _roll(table: Array, roll: float) -> String:
	for entry: Array in table:
		if roll < float(entry[0]):
			return String(entry[1])
	return ""


func _loot(key: String, id: String) -> void:
	if has(id):
		pending_loot[key] = id
		desk_used.erase(key)
		_say("我：这里有「%s」。我已经带着一份，先把它留在这里。" % item_name(id))
		return
	if add(id):
		desk_used[key] = true
		pending_loot.erase(key)


func do_search(room_id: String, c: int, r: int) -> void:
	var key := "%s:%d:%d" % [room_id, c, r]
	if desk_used.has(key):
		return
	if bag.size() >= capacity():
		_say("我：装不下了。先腾出一个空位再翻。")
		return
	if pending_loot.has(key):
		_loot(key, String(pending_loot[key]))
		return
	desk_used[key] = true
	var room: Dictionary = _rooms.get(room_id, {})
	var principal := bool(room.get("flags", {}).get("principal", false))
	if room.get("host") == "admin":
		var miss: Array = []
		for k: String in ["key", "roomkey"]:
			if not has(k):
				miss.append(k)
		var pity := principal and key_miss >= 3
		if not miss.is_empty() and (pity or _rng.randf() < (0.45 if principal else 0.01)):
			key_miss = 0
			var kk := String(miss[int(floor(_rng.randf() * miss.size()))])
			_say("我：抽屉最里面压着一串车钥匙，牌号刻在环上。" if kk == "key" else "我：抽屉里有一把铜钥匙，塑料标签上写着「机房」。")
			add(kk)
			return
		if not miss.is_empty() and principal:
			key_miss += 1
		if principal:
			var pr := _rng.randf()
			if pr < 0.12 and not has("atlas"):
				_say("我：抽屉里卷着一大张图纸，是整个学校每一层的平面图。")
				add("atlas")
				return
			if pr < 0.18 and not has("elixir"):
				_say("我：一个空药盒里只剩一粒药丸，盒子上的字被刮掉了。")
				add("elixir")
				return
	var grid: Array = room.get("grid", [])
	if room_id == "lab3" and r < grid.size() and String(grid[r]).substr(c, 1) == "R" and not has("usb"):
		_say("我：货架最上层有个文件盒，里面躺着一个 U 盘。标签上写着「门禁」。")
		add("usb")
		return
	if room.get("host") == "lab":
		var table: Variant = _campus.get("lab_loot", {}).get(str(int(room.get("floor", 0))))
		var lv := _roll(table, _rng.randf()) if table is Array else ""
		if lv.is_empty():
			_say("我：空的。抽屉里只有一层灰。")
		else:
			_loot(key, lv)
		return
	var give := _roll(_campus.get("desk_loot", []), _rng.randf())
	if room_id == "teach1" and not hw_taken and r > 1 and r < 14:
		hw_taken = true
		give = "hw"
	if not give.is_empty():
		_loot(key, give)
	else:
		_say(EMPTY_LINES[_rng.randi() % EMPTY_LINES.size()])


## interact.js 'T': the own classroom's podium holds the handover note (InvestigationModule.notice, handled by the app);
## other podiums in teach1 have a piece of chalk.
func podium(room_id: String, c: int, r: int) -> Dictionary:
	var own: Array = _campus.get("own_podium", [])
	if room_id == "teach1" and own.size() == 2 and int(own[0]) == c and int(own[1]) == r:
		return {"notice": ""}
	if room_id == "teach1":
		if has("chalk"):
			return {"notice": "我：讲台上有一支粉笔，我已经带了一支。"}
		if add("chalk"):
			_notices.remove_at(_notices.size() - 1)
			return {"notice": "我：讲台上有一支粉笔。"}
		return {}
	return {"notice": "我：讲台是空的。"}
