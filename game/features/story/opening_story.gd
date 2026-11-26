class_name OpeningStory
extends RefCounted
## Shared wording for the classroom opening, the handover and the personal notebook.

const SIGNATURE := "这笔是我自己的。我刚在试卷的姓名栏这样写过。"
const LESSON := "请先在姓名栏写下自己的名字。"
const CLASSROOM := "我交了卷。老师收走它，我把脸埋进校服袖子，趴在课桌上睡着了。"
const WAKE := "我在自己的课桌上醒来。阳光没了。前面一排人的手同时抬起，又同时落下。笔尖始终没碰到纸。"
const NEXT := "桌角的名牌底下压着一张点名联。我先看看自己的名字，再去北门旁的保安岗查底联。"
const FIRST_LEAD := "低头看课桌上的名牌，再去北门旁的保安岗核对点名底联。"
const PERSONAL_MEMORY := {
	"lin": "上课前，我在书页角上画了个取景框。监考老师进来，我把书收到桌肚里。",
	"qiao": "我从操场回来的时候，鞋缝里还有红色的跑道砂。平时一响铃，我总是头一个冲到楼下。",
	"shen": "考试前我还在算一道物理题。受力图画好了，最后一步没算完。",
	"xu": "我在广播站帮过值日。下课铃响之前，喇叭总会先冒出一声很轻的电流音。",
}


static func student_name(character: String) -> String:
	return StudentCast.PEOPLE[StudentCast.resolve(character)]["name"]


static func identity(character: String, cooperative: bool = false) -> String:
	var name := student_name(character)
	if cooperative: return "我叫%s，武大附中高二（二）班。" % name
	return "我叫%s，这学期转到武大附中，高二（二）班。" % name


static func captions(character: String, short: bool) -> PackedStringArray:
	var name := student_name(character)
	if short:
		return PackedStringArray(["", "", "", "试卷收上去了。我是%s。我趴了一会儿，睡着了。" % name,
			"我醒了。铃没有响，所有人的笔却同时落下。", "我的名牌还在。底下压了一张点名联。"])
	return PackedStringArray([identity(character), "窗外响着哨声，课代表正把试卷往后传。",
		"我在姓名栏写下了「%s」。" % name, CLASSROOM, WAKE, NEXT])


static func pages(character: String) -> PackedStringArray:
	return PackedStringArray([identity(character), "老师走过来，把试卷放在我桌上。窗外传来操场上的哨声。",
		"我在姓名栏写下了「%s」，坐在原位答完六科综合测验。" % student_name(character),
		CLASSROOM, WAKE, NEXT])


static func handover(character: String) -> String:
	return "我叫%s。桌上的名牌也是我的名字。先低头看看，再去北门旁的保安岗查底联。" % student_name(character)


static func background(character: String, cooperative: bool = false) -> String:
	var paragraphs := pages(character)
	paragraphs[0] = identity(character, cooperative)
	paragraphs.insert(1, PERSONAL_MEMORY[StudentCast.resolve(character)])
	if cooperative: paragraphs.append("醒来后，只有和我一起答卷的队友能自由行动。")
	return "\n\n".join(paragraphs)
