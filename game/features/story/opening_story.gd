class_name OpeningStory
extends RefCounted
## Shared wording for the classroom opening, the handover and the personal notebook.

const RELATIONSHIP := "刚来的时候我走错过楼层，是同桌把我领回教室的。"
const APPOINTMENT := "今天说好了，放学陪他去北门接妹妹。家里也留了我的晚饭。"
const PAPER := "第四节课前，他把一张停车单塞到我书底下。上联四边都是齐的，右上角印着「17 号工单」。"
const SIGNATURE := "签名最后一笔往回勾，和我写的一模一样。我记得今天只在班里的签到册上签过字。"
const NOTE := "纸背上有他写的一行字。「底联在北门旁的保安岗。你去看一眼，点到你，我替你应一声。」"
const LESSON := "雨停以后，檐下还在滴水。"
const CLASSROOM := "「" + LESSON + "」老师把课文里同一句话念了第二遍。我趴到桌上。"
const WAKE := "再抬头时，教室里还是坐满了人，身边那个长得像同桌的人一直盯着讲台，连胸口都一动不动。"
const SILENCE := "下课铃没有响。纸条还在我手边。"
const NEXT := "我得先去北门旁的保安岗，看看那张底联，再找一条能回家的路。"
const FIRST_LEAD := "去北门旁的保安岗柜台看底联，认一认上面的签名。"
const PERSONAL_MEMORY := {
	"lin": "上课前，我在书页角上画了个取景框。放学路过北门时，我想给同桌和他妹妹拍张照。",
	"qiao": "我从操场回来的时候，鞋缝里还有红色的跑道砂。平时一响铃，我总是头一个冲到楼下。",
	"shen": "我刚给同桌讲完半道物理题。草稿还搁在我们两张桌子的接缝上。",
	"xu": "我在广播站帮过值日。下课铃响之前，喇叭总会先冒出一声很轻的电流音。",
}


static func student_name(character: String) -> String:
	return StudentCast.PEOPLE[StudentCast.resolve(character)]["name"]


static func identity(character: String, cooperative: bool = false) -> String:
	var name := student_name(character)
	if cooperative: return "我叫%s，武大附中高二（二）班。" % name
	return "我叫%s，这学期转到武大附中，高二（二）班。" % name


static func captions(character: String, short: bool) -> PackedStringArray:
	if short:
		return PackedStringArray(["", "", "", "我是%s。语文老师又念了一遍。" % student_name(character),
			"一抬头，旁边那人长得像同桌，胸口一动不动。", "铃没响。去保安岗查底联。"])
	return PackedStringArray([
		"我叫%s，刚转来武大附中高二（二）班。" % student_name(character),
		"放学陪同桌去北门接妹妹。家里留了我的晚饭。",
		"同桌递来停车单。17 号工单，签名那一勾是我的。",
		"「" + LESSON + "」老师又念了一遍。我趴到桌上。",
		"再抬头，身边那人长得像同桌，胸口一动不动。",
		"下课铃没有响。纸条还在。",
	])


static func pages(character: String) -> PackedStringArray:
	return PackedStringArray([identity(character) + RELATIONSHIP, APPOINTMENT,
		PAPER + SIGNATURE, NOTE, CLASSROOM, WAKE, SILENCE, NEXT])


static func handover(character: String) -> String:
	return "我是%s，家里还等我。\n先去北门旁的保安岗查底联，再找回家的路。" % student_name(character)


static func background(character: String, cooperative: bool = false) -> String:
	var paragraphs := pages(character)
	if cooperative:
		paragraphs = PackedStringArray([identity(character, true),
			"我们约好放学一起走北门。有同学要接妹妹，家里也留了我的晚饭。",
			"第四节课前，有人把停车单发给我们。上联四边都是齐的，每份签着收件人的名字，都印着「17 号工单」。" + SIGNATURE,
			"纸背上写着，底联在北门旁的保安岗。",
			CLASSROOM, "再抬头时，有几个同学也醒了。还有一排人盯着讲台，胸口一动不动。",
			SILENCE, NEXT])
	paragraphs.insert(1, PERSONAL_MEMORY[StudentCast.resolve(character)])
	return "\n\n".join(paragraphs)
