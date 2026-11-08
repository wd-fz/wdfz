class_name CameraModule
extends FeatureModule
## The phone camera, ported from the Web version (reference wd-fz.github.io@0bf508a,
## modules/phone-camera/camera.js): taking a photo costs no battery and changes no anomaly's rules.
## A photo shows what is really there, plus — only while an anomaly is happening — one extra thing that
## appears in photos only (the PHOTO table); with nothing happening the photo shows nothing extra. The
## album keeps the last 6 (the small image is saved with the run). The flash is on by default: a patroller
## that can see you within 1.6× its sight range is drawn over (lock almost full, your spot remembered);
## with the flash off the photo is darker and nothing comes. Reduce-flash only dims the white flash.
## Events out: say {text}, record {...}, fact {an, flash, seen}.

const STATE_VERSION := 1
const KEEP := 6
const W := 192
const H := 108
const FLASH_SEE := 1.6
const FLASH_LOCK := 0.85
const PHOTO := {
	"blackout": {"k": "eyes", "cap": "黑暗里有很多双眼睛，都在同一个高度。"},
	"rain": {"k": "figure", "cap": "雨幕后面站着一个没打伞的人，身上是干的。"},
	"moth": {"k": "face", "cap": "蛾子聚成了一张脸。"},
	"turn": {"k": "behind", "cap": "我肩膀后面有一个影子，比我高一个头。"},
	"broad": {"k": "text", "cap": "喇叭下面的墙上写着我的名字。", "text": "高二（二）班"},
	"bell13": {"k": "face", "cap": "钟楼的窗口里，有一张脸贴在钟上。"},
	"exercise": {"k": "crowd", "cap": "做操的人全都面朝镜头。"},
	"bells": {"k": "hands", "cap": "每一个车铃上都按着一只手。"},
	"hand": {"k": "hands", "cap": "隔间底下伸出来的不是一只手，是三只。"},
	"repeat": {"k": "figure", "cap": "问我作业的那个人，脚下没有影子。"},
	"chalk": {"k": "text", "cap": "黑板上多了一行：「拍照的那个」。", "text": "拍照的那个"},
	"loop": {"k": "figure", "cap": "走廊尽头站着一个人，穿着和我一样的校服。"},
	"roster": {"k": "text", "cap": "名单上被划掉的那一行，写的是今天的日期。", "text": "今天"},
	"leak": {"k": "face", "cap": "天花板上的水渍，是一张往下看的脸。"},
	"rite": {"k": "crowd", "cap": "围成一圈的人中间空着一个位置，正好是我站的地方。"},
	"cold": {"k": "figure", "cap": "冷库最里面坐着一个人，在朝我招手。"},
	"shifting": {"k": "face", "cap": "对面那栋楼，每一扇窗户里都有一个人。"},
	"stare": {"k": "eyes", "cap": "所有人都在看镜头，包括我座位上的那个。"},
	"lamps": {"k": "figure", "cap": "每一盏亮着的灯底下，都站着一个人。"},
	"feast": {"k": "seated", "cap": "空着的餐桌边坐满了人，盘子里什么也没有。"},
	"necker": {"k": "face", "cap": "围墙上方探出来的那个头，脖子很长。"},
	"shadow": {"k": "behind", "cap": "地上我的影子，脸朝着镜头。"},
	"twin": {"k": "figure", "cap": "天台边上的那个人，也举着手机在拍我。"},
	"raindots": {"k": "text", "cap": "地上的雨点拼成了两个字：「别拍」。", "text": "别拍"},
	"cup": {"k": "hands", "cap": "窗台上的杯子旁边，有一只手正要推它。"},
	"window_gaze": {"k": "eyes", "cap": "窗玻璃上那双眼睛，在照片里是闭着的。"},
	"cola": {"k": "figure", "cap": "楼顶边上蹲着一个人，手里拿着一罐东西。", "secret": true},
	"crowd": {"k": "crowd", "cap": "电梯里挤满了人，全都面朝门。", "secret": true}
}

var photos: Array = []        # newest first: {an, cap, img (base64 JPEG), day, t, place, flash}
var flash := true
var events: Array = []

var _c: Dictionary = {}


func module_id() -> StringName:
	return &"phone.camera"


func state_version() -> int:
	return STATE_VERSION


func reset() -> void:
	photos = []
	flash = true
	events = []


func capture() -> Dictionary:
	return {"photos": photos.duplicate(true), "flash": flash}


func validate(data: Dictionary) -> String:
	if not (data.get("photos", []) is Array) or (data["photos"] as Array).size() > KEEP or not (data.get("flash", true) is bool):
		return "相册无效"
	for p: Variant in data["photos"]:
		if not (p is Dictionary) or not (p.get("cap") is String) or not (p.get("img") is String) or String(p["img"]).length() > 120000 \
				or not SaveSchema.is_integer(p.get("day"), 1, 1000) or not (p.get("place") is String):
			return "相册无效"
	return ""


func restore(data: Dictionary) -> void:
	reset()
	photos = (data.get("photos", []) as Array).duplicate(true)
	flash = bool(data.get("flash", true))


## ctx: an (the active anomaly id or ""), gaze (the window-gaze event is on), crowd, day, tsec, place, clock (the watch shows the time).
func set_context(ctx: Dictionary) -> void:
	_c = ctx


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(kind: String, payload: Dictionary = {}) -> void:
	var e := payload.duplicate()
	e["kind"] = kind
	events.append(e)


## What is in the lens right now: the lift crowd, the window's eyes, or a running anomaly that has a photo.
func subject() -> String:
	if bool(_c.get("crowd", false)):
		return "crowd"
	if bool(_c.get("gaze", false)):
		return "window_gaze"
	var an := String(_c.get("an", ""))
	return an if PHOTO.has(an) else ""


## The plan of the next photo: which extra layer to draw and the caption.
func plan() -> Dictionary:
	var an := subject()
	var def: Dictionary = PHOTO.get(an, {})
	var seed := DreadModule.lhash("%s:%d:%d" % [an, int(_c.get("day", 1)), roundi(float(_c.get("tsec", 0.0)))]) * 4294967296.0
	return {"an": an, "flash": flash, "kind": String(def.get("k", "")), "text": String(def.get("text", "")), "seed": int(seed), "noise": roundi(float(_c.get("tsec", 0.0)) * 7.0) + 3,
		"cap": ("照片里，" + String(def["cap"])) if not def.is_empty() else "照片里什么也没有。",
		"stamp": "%s  D%d" % [SchoolClock.fmt_clock(float(_c.get("tsec", 0.0))) if bool(_c.get("clock", false)) else "--:--", int(_c.get("day", 1))]}


## The finished photo goes into the album. seen: the flash drew the patroller over.
func add_photo(p: Dictionary, img_b64: String, seen: bool) -> void:
	var rec := {"an": p["an"], "cap": p["cap"], "img": img_b64, "day": int(_c.get("day", 1)), "t": roundi(float(_c.get("tsec", 0.0))), "place": String(_c.get("place", "")), "flash": 1 if bool(p["flash"]) else 0}
	photos.push_front(rec)
	while photos.size() > KEEP:
		photos.pop_back()
	var def: Dictionary = PHOTO.get(String(p["an"]), {})
	_emit("say", {"text": "我：咔嚓。" + ("我低头看了一眼照片。" + String(p["cap"]) if not def.is_empty() else "") + ("\n闪光一亮，走廊那头的脚步停了一下，转了过来。" if seen else ""), "long": not def.is_empty()})
	if not def.is_empty() and not bool(def.get("secret", false)):
		_emit("record", {"id": "photo_" + String(p["an"]), "text": "手机里的照片（%s）：%s" % [rec["place"], p["cap"]], "kind": "线索", "source": rec["place"]})
	_emit("fact", {"what": "photo", "an": p["an"], "flash": bool(p["flash"]), "seen": seen})


func toggle_flash() -> void:
	flash = not flash


func copy_text() -> String:
	return "拍照不耗电。闪光" + ("开着：照片亮一些，但巡察者看得见你的话，会被闪光引过来。" if flash else "关着：照片暗一些，不会引来巡察者。") \
		+ "\n相册（最近 %d 张）：" % KEEP + ("%d 张" % photos.size() if not photos.is_empty() else "还没有照片。")
