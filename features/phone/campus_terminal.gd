class_name CampusTerminal
extends RefCounted
## The simulated maintenance shell of the cyber route (domain/campus-terminal.js, reference
## wd-fz.github.io@0bf508a): read-only /school files generated from the run seed, a writable
## /work, a handful of text commands and `campusctl` with the four steps T1–T4. No real shell.

const LIMIT := 8192
const HELP := "可用命令：help、man campusctl、pwd、ls -a [路径]、cd 路径、cat 文件、grep 字串 [文件]、head/tail [-n 数量] [文件]、sort [文件]、cp 源 /work/目标、mkdir /work/目录、edit /work/文件 \"内容\"。\n引号内用 \\n 换行；管道最多四段，仅 cat/grep/head/tail/sort。"
const MAN := "T1: campusctl select 控制器 /school/assets.tsv\nT2: campusctl trace 事务 /school/runtime.log\nT3: edit /work/shutdown \"controller=代号\\ntransaction=事务\\ntoken=回执\\nclock=active\\nstop 功能模块\\nstop 功能模块\\nstop 功能模块\"，然后 campusctl validate /work/shutdown\nT4: campusctl shutdown --confirm\n提示：campusctl hint 1 / campusctl hint 2；进度：campusctl status"


static func fnv(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


static func base36(n: int) -> String:
	var digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	if n == 0:
		return "0"
	var out := ""
	while n > 0:
		out = digits[n % 36] + out
		n /= 36
	return out


## JavaScript's signed `>>` on a 32-bit unsigned value (the old code relies on it).
static func _sr(n: int, k: int) -> int:
	var signed := n - 4294967296 if n >= 2147483648 else n
	return signed >> k


static func make(seed_value: String, attempt: int) -> Dictionary:
	var n := fnv("%s:%d" % [seed_value, attempt])
	var zone := "Z%d" % (10 + n % 79)
	var batch := "B%d" % (100 + _sr(n, 8) % 899)
	var controller := "ctl-%d" % (1000 + n % 8999)
	var tx := "TX-%d" % (10000 + _sr(n, 3) % 89999)
	var word := "ack-" + base36(n)
	var mods: Array = ["attendance", "doors", "observation"]
	if n % 2 == 1:
		mods.reverse()
	if n % 3 == 0:
		mods.append(mods.pop_front())
	var files := {
		"/school/README": "校园维护环境（模拟 Kali Linux 容器）\n只读 /school，可写 /work。help 查看命令；man campusctl 查看提交格式。\n先用区域、批次和资产清单确认当前控制器，再关联日志中的同一事务，最后按服务依赖写出停机清单。",
		"/school/site.txt": "试点区域=%s\n当前运行批次=%s\n部署日期=2026-09-01" % [zone, batch],
		"/school/assets.tsv": "id zone batch role status\nmirror-%d %s %s mirror online\nctl-old %s B099 controller retired\n%s %s %s controller online\nctl-decoy Z00 %s controller online" % [n % 100, zone, batch, zone, controller, zone, batch, batch],
		"/school/runtime.log": "calendar=11:40 active=100 tx=TX-noise node=mirror actor=observer event=prepare\n" +
			"calendar=12:50 active=124 tx=%s node=%s actor=control event=commit token=%s\n" % [tx, controller, word] +
			"calendar=11:32 active=118 tx=%s node=%s actor=control event=authorize\n" % [tx, controller] +
			"calendar=11:40 active=110 tx=%s node=%s actor=control event=prepare\n" % [tx, controller] +
			"calendar=12:50 active=125 tx=TX-noise node=%s actor=observer event=commit token=invalid" % controller,
		"/school/services.txt": "维护协议：功能服务依次解除依赖，控制层 control 保留到提交之后，由服务器最后关闭。\n依赖关系 A -> B 表示必须先停 A 才能停 B。\n%s -> %s\n%s -> %s" % [mods[0], mods[1], mods[1], mods[2]],
		"/school/company.txt": "AnthroPrank AI（安抄派智能）\n行为一致性与秩序对齐试点。名单、门禁、巡察是我们的可操作控制系统。\n创世报告声称第一次部署之前没有异常，所有巡察均由控制器产生。",
		"/school/archive.txt": "纸质档案扫描：1987 年，走廊里第二次出现不在值班表上的人。\n断链故障记录：控制链已离线，仍收到无法对应签发节点的回执。\n注销字段原始定义：转交上层保管；不是删除。",
	}
	return {"files": files, "answer": {"controller": controller, "tx": tx, "token": word, "order": mods, "zone": zone, "batch": batch}}


static func fresh(seed_value: String, attempt: int = 1) -> Dictionary:
	return {"version": 1, "runSeed": seed_value, "attemptId": attempt, "cwd": "/school", "work": {}, "dirs": ["/work"], "controllerId": null,
		"chainId": null, "evidence": [], "validated": null, "acceptedRequestId": null, "helpRead": false, "hint": 0, "buffer": "", "history": []}


static func path(s: Dictionary, p: String) -> String:
	if p == "":
		p = String(s["cwd"])
	var full := p if p.begins_with("/") else String(s["cwd"]) + "/" + p
	var out: Array = []
	for x: String in full.split("/"):
		if x == "..":
			if not out.is_empty():
				out.pop_back()
		elif x != "" and x != ".":
			out.append(x)
	return "/" + "/".join(PackedStringArray(out))


static func read(s: Dictionary, p: String) -> Variant:
	p = path(s, p)
	var files: Dictionary = make(String(s["runSeed"]), int(s["attemptId"]))["files"]
	if files.has(p):
		return files[p]
	return (s["work"] as Dictionary).get(p)


## Split a command line into words; returns {words} or {error}.
static func words(line: String) -> Dictionary:
	var out: Array = []
	var cur := ""
	var quote := ""
	var started := false
	for i in line.length():
		var c := line.substr(i, 1)
		if quote != "":
			if c == quote:
				quote = ""
			else:
				cur += c
			started = true
		elif c == "\"" or c == "'":
			quote = c
			started = true
		elif c == " " or c == "\t" or c == "\n":
			if started:
				out.append(cur)
				cur = ""
				started = false
		elif c == "|":
			if started:
				out.append(cur)
				cur = ""
				started = false
			out.append("|")
		elif ";<>`&$".contains(c):
			return {"error": "不支持 shell 展开、重定向或执行语法。使用 edit 写 /work 文件。"}
		else:
			cur += c
			started = true
	if quote != "":
		return {"error": "引号未闭合。"}
	if started:
		out.append(cur)
	return {"words": out}


static func _writable(s: Dictionary, p: String) -> Dictionary:
	p = path(s, p)
	if not p.begins_with("/work/"):
		return {"error": "只允许写 /work/ 下的文件。"}
	if p.length() > 160 or p.split("/").size() > 10:
		return {"error": "路径过长。"}
	return {"path": p}


static func _write(s: Dictionary, p: String, value: String) -> Dictionary:
	var w := _writable(s, p)
	if w.has("error"):
		return w
	if value.length() > LIMIT:
		return {"error": "文件上限 8192 字符。"}
	if not (s["work"] as Dictionary).has(w["path"]) and (s["work"] as Dictionary).size() >= 32:
		return {"error": "工作区最多 32 个文件。"}
	s["work"][w["path"]] = value
	s["validated"] = null
	return w


static func validate(s: Dictionary, p: String) -> Dictionary:
	var a: Dictionary = make(String(s["runSeed"]), int(s["attemptId"]))["answer"]
	var body: Variant = read(s, p)
	var errors: Array = []
	if s["controllerId"] != a["controller"] or not (s["evidence"] as Array).has("/school/assets.tsv"):
		errors.append("T1：尚未确认有效的控制器与资产证据。")
	if s["chainId"] != a["tx"] or not (s["evidence"] as Array).has("/school/runtime.log"):
		errors.append("T2：尚未确认同一控制层事务的完整日志链。")
	if not (body is String):
		errors.append("清单文件不存在。")
		return {"ok": false, "errors": errors}
	var values := {}
	var stops: Array = []
	for raw: String in String(body).split("\n"):
		var l := raw.strip_edges()
		if l == "":
			continue
		var m := RegEx.create_from_string("^(controller|transaction|token|clock)=(\\S+)$").search(l)
		var st := RegEx.create_from_string("^stop (\\S+)$").search(l)
		if m != null:
			if values.has(m.get_string(1)):
				errors.append("重复字段：" + m.get_string(1))
			values[m.get_string(1)] = m.get_string(2)
		elif st != null:
			stops.append(st.get_string(1))
		else:
			errors.append("无法识别的清单行：" + l)
	for v: Array in [["controller", a["controller"]], ["transaction", a["tx"]], ["token", a["token"]], ["clock", "active"]]:
		if values.get(v[0]) != v[1]:
			errors.append("%s：缺失或与证据不符。" % v[0])
	if ",".join(PackedStringArray(stops)) != ",".join(PackedStringArray(a["order"])):
		errors.append("stop：必须按服务依赖顺序关闭三个功能模块，保留 control。")
	return {"ok": errors.is_empty(), "errors": errors, "body": body}


static func _ctl(s: Dictionary, args: Array) -> Dictionary:
	var a: Dictionary = make(String(s["runSeed"]), int(s["attemptId"]))["answer"]
	var verb := String(args[0]) if not args.is_empty() else ""
	match verb:
		"hint":
			var level := clampi(int(args[1]) if args.size() > 1 and String(args[1]).is_valid_int() else 1, 1, 2)
			s["hint"] = maxi(int(s["hint"]), level)
			return {"text": "先读 site.txt、assets.tsv、runtime.log、services.txt；档案叙事在 company.txt 和 archive.txt。" if level == 1 else
				"用区域和当前批次排除镜像与旧节点；日志按相同事务、控制器及 control 角色关联，再按 active 数字排列 prepare → authorize → commit，取最后回执。依赖箭头给出三个 stop 的先后。"}
		"status":
			return {"text": "T1 %s · T2 %s · T3 %s · T4 %s" % [s["controllerId"] if s["controllerId"] != null else "未确认", s["chainId"] if s["chainId"] != null else "未关联",
				"清单已校验" if s["validated"] != null else "未校验", s["acceptedRequestId"] if s["acceptedRequestId"] != null else "未提交"]}
		"select":
			if args.size() < 3 or args[1] != a["controller"] or path(s, String(args[2])) != "/school/assets.tsv":
				return {"error": "控制器与证据不匹配；核对区域、运行批次、角色与有效状态。"}
			s["controllerId"] = args[1]
			if not (s["evidence"] as Array).has("/school/assets.tsv"):
				s["evidence"].append("/school/assets.tsv")
			s["validated"] = null
			return {"text": "T1 控制器已确认。"}
		"trace":
			if s["controllerId"] != a["controller"]:
				return {"error": "先确认 T1 控制器。"}
			if args.size() < 3 or args[1] != a["tx"] or path(s, String(args[2])) != "/school/runtime.log":
				return {"error": "事务没有完整的控制层日志链。注意角色、校历与运行秒。"}
			s["chainId"] = args[1]
			if not (s["evidence"] as Array).has("/school/runtime.log"):
				s["evidence"].append("/school/runtime.log")
			s["validated"] = null
			return {"text": "T2 日志链已确认。请把回执与时间口径写入清单。"}
		"validate":
			var w := _writable(s, String(args[1]) if args.size() > 1 else "/work/shutdown")
			if w.has("error"):
				return w
			var v := validate(s, w["path"])
			s["validated"] = {"path": w["path"], "digest": fnv(String(v.get("body", "")))} if v["ok"] else null
			return {"text": "T3 校验通过。提交后须存活十分钟；可以断开手机。输入 campusctl shutdown --confirm 明确提交。" if v["ok"] else "\n".join(PackedStringArray(v["errors"]))}
		"shutdown":
			if args.size() != 2 or args[1] != "--confirm":
				return {"error": "提交需要 --confirm；接受后必须存活十分钟。"}
			if s["validated"] == null:
				return {"error": "先通过 T1—T3 并校验清单。"}
			var check := validate(s, String(s["validated"]["path"]))
			if not check["ok"] or fnv(String(check["body"])) != int(s["validated"]["digest"]):
				return {"error": "清单或证据改变，请重新校验。"}
			return {"text": "服务器已接受此请求；不会重新计时。" if s["acceptedRequestId"] != null else "服务器接受停机请求，开始 600 运行秒生存阶段。", "request": "shutdown"}
	return {"error": "未知 campusctl 子命令。输入 man campusctl。"}


static func _command(s: Dictionary, argv: Array, input: String) -> Dictionary:
	var cmd := String(argv.pop_front())
	var files: Dictionary = make(String(s["runSeed"]), int(s["attemptId"]))["files"]
	match cmd:
		"help":
			s["helpRead"] = true
			return {"text": HELP}
		"man":
			return {"text": MAN if not argv.is_empty() and argv[0] == "campusctl" else HELP}
		"pwd":
			return {"text": s["cwd"]}
		"ls":
			var rest: Array = argv.filter(func(x: String) -> bool: return x != "-a")
			var p := path(s, String(rest[0]) if not rest.is_empty() else "")
			var all: Array = files.keys() + (s["work"] as Dictionary).keys() + (s["dirs"] as Array) + ["/school", "/work"]
			var names: Array = []
			var prefix := "/" if p == "/" else p + "/"
			for x: String in all:
				if x.begins_with(prefix):
					var name := x.substr(prefix.length()).split("/")[0]
					if name != "" and not names.has(name):
						names.append(name)
			names.sort()
			return {"text": "\n".join(PackedStringArray(names))}
		"cd":
			var p := path(s, String(argv[0]) if not argv.is_empty() else "")
			if p != "/" and p != "/school" and not (s["dirs"] as Array).has(p):
				return {"error": "目录不存在。"}
			s["cwd"] = p
			return {"text": ""}
		"mkdir":
			if argv.size() != 1:
				return {"error": "用法：mkdir /work/目录"}
			var w := _writable(s, String(argv[0]))
			if w.has("error"):
				return w
			if (s["dirs"] as Array).size() >= 32:
				return {"error": "目录数量已达上限。"}
			if not (s["dirs"] as Array).has(w["path"]):
				s["dirs"].append(w["path"])
			return {"text": w["path"]}
		"edit":
			if argv.size() != 2:
				return {"error": "用法：edit /work/文件 \"内容\"，用 \\n 换行。"}
			var w := _write(s, String(argv[0]), String(argv[1]).replace("\\n", "\n"))
			return w if w.has("error") else {"text": "已保存 " + w["path"]}
		"cp":
			if argv.size() != 2:
				return {"error": "用法：cp 源文件 /work/目标"}
			var data: Variant = read(s, String(argv[0]))
			if data == null:
				return {"error": "源文件不存在。"}
			var w := _write(s, String(argv[1]), String(data))
			return w if w.has("error") else {"text": "已复制 " + w["path"]}
		"campusctl":
			return _ctl(s, argv)
	if not cmd in ["cat", "grep", "head", "tail", "sort"]:
		return {"error": "不支持的命令。输入 help 查看本模拟环境的命令。"}
	var pattern := ""
	var count := 10
	if cmd == "grep":
		if argv.is_empty():
			return {"error": "grep 需要字串（按原文匹配）。"}
		pattern = String(argv.pop_front())
	if (cmd == "head" or cmd == "tail") and not argv.is_empty() and argv[0] == "-n":
		argv.pop_front()
		var nstr := String(argv.pop_front()) if not argv.is_empty() else ""
		if not nstr.is_valid_int() or int(nstr) < 0 or int(nstr) > 200:
			return {"error": "-n 范围为 0—200。"}
		count = int(nstr)
	if argv.size() > 1:
		return {"error": "每段命令只接受一个文件；使用管道连接。"}
	var text: Variant = read(s, String(argv[0])) if not argv.is_empty() else (input if input != "" else null)
	if not (text is String):
		return {"error": "文件不存在或管道没有输入。"}
	if cmd == "cat":
		return {"text": text}
	var lines: Array = Array(String(text).split("\n"))
	if cmd == "grep":
		lines = lines.filter(func(l: String) -> bool: return l.contains(pattern))
	if cmd == "sort":
		lines.sort()
	if cmd == "head":
		lines = lines.slice(0, count)
	if cmd == "tail":
		lines = lines.slice(maxi(0, lines.size() - count)) if count > 0 else []
	return {"text": "\n".join(PackedStringArray(lines))}


## Run one line. Returns {text, error?, request?}.
static func run(s: Dictionary, line: String) -> Dictionary:
	if line.length() > 4096:
		return {"text": "错误：输入最多 4096 字符。", "error": true}
	var w := words(line)
	if w.has("error"):
		return {"text": "错误：" + String(w["error"]), "error": true}
	var parts: Array = [[]]
	for t: String in w["words"]:
		if t == "|":
			parts.append([])
		else:
			parts[parts.size() - 1].append(t)
	if parts.size() > 4 or parts.any(func(p: Array) -> bool: return p.is_empty()):
		return {"text": "错误：管道最多四段，且不能留空。", "error": true}
	if parts.size() > 1 and parts.any(func(p: Array) -> bool: return not String(p[0]) in ["cat", "grep", "head", "tail", "sort"]):
		return {"text": "错误：管道仅支持 cat/grep/head/tail/sort。", "error": true}
	var out := {"text": ""}
	for p: Array in parts:
		out = _command(s, p.duplicate(), String(out.get("text", "")))
		if out.has("error"):
			return {"text": "错误：" + String(out["error"]), "error": true}
	out["text"] = String(out.get("text", "")).substr(0, LIMIT)
	return out
