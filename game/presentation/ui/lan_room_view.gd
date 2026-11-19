class_name LanRoomView
extends RefCounted
## Read-only room labels. Network timing and authority remain in LanSession.
const COLORS := [Color("91c7b5"), Color("a5bce8"), Color("e5c18c"), Color("d8a6c7")]


static func color(id: String) -> Color:
	return COLORS[posmod(id.hash(), COLORS.size())]


static func active_members(state: Dictionary) -> Array:
	return state.get("members", {}).values().filter(func(m: Dictionary) -> bool: return m.get("state") != "departed")


static func ordered_ids(state: Dictionary, local_id: String) -> Array:
	var ids: Array = state.get("members", {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var rank_a := 0 if a == state.get("host") else 1 if a == local_id else 2
		var rank_b := 0 if b == state.get("host") else 1 if b == local_id else 2
		return rank_a < rank_b if rank_a != rank_b else a < b)
	return ids


static func start_hint(state: Dictionary) -> String:
	var people := active_members(state)
	var minimum := int(state.get("minimum_loaded", 2))
	if people.size() < minimum: return "等待好友加入（至少 %d 人）" % minimum
	for m: Dictionary in people:
		if not m.get("connected", false): return "等待 %s 重连" % m.get("name", "队友")
	var waiting := people.filter(func(m: Dictionary) -> bool: return not m.get("ready", false))
	if not waiting.is_empty(): return "等待准备 · %d/%d" % [people.size() - waiting.size(), people.size()]
	return ""


static func summary(state: Dictionary) -> String:
	var people := active_members(state)
	match state.get("phase", "lobby"):
		"loading":
			if people.size() < int(state.get("minimum_loaded", 2)): return "人数不足，无法开始；请返回主菜单重新创建房间。"
			var ready := people.filter(func(m: Dictionary) -> bool: return m.get("state") == "alive" and m.get("connected", false)).size()
			return "准备校园 · %d/%d 人完成，全部就绪后一起开始" % [ready, people.size()]
		"playing":
			if float(state.get("paused", 0)) > 0: return "全队暂停 · %d 秒后自动继续" % ceili(float(state["paused"]))
			return "个人菜单不会暂停队友 · 靠近队友可交付物品"
		"ended": return "本局已结束 · 返回主菜单后可开始新的合作"
	return "全员准备就绪，房主可以开始。" if start_hint(state).is_empty() else start_hint(state)


static func member_text(id: String, m: Dictionary, state: Dictionary, local_id: String, nearby: Dictionary = {}) -> String:
	var who := String(m.get("name", "同学")) + ("（你）" if id == local_id else "") + (" · 房主" if id == state.get("host") else "")
	if StudentCast.valid(m.get("character")): who += " · " + String(StudentCast.PEOPLE[m["character"]]["name"])
	var detail := ""
	if m.get("state") == "departed": detail = "已离队"
	elif not m.get("connected", false): detail = "暂时断线 · 角色保留 %d 秒" % ceili(float(m.get("remaining", 0)))
	elif state.get("phase") == "loading": detail = "已就绪" if m.get("state") == "alive" else "正在准备校园"
	elif state.get("phase") == "ended": detail = "本局已结束"
	elif m.get("state") == "dead": detail = "观战中"
	elif state.get("phase") == "lobby": detail = "已准备" if m.get("ready", false) else "选择天赋后准备"
	else: detail = "探索中"
	var gift: Dictionary = TalentModule.DEF.get(m.get("talent", "none"), {})
	if not gift.is_empty(): detail += " · " + String(gift["n"])
	if not nearby.is_empty() and m.get("state") != "departed":
		detail += "\n" + String(nearby.get("place", ""))
		if id != local_id and float(nearby.get("distance", -1)) >= 0: detail += " · 距你 %d 米" % roundi(float(nearby["distance"]))
	return who + "\n" + detail
