class_name CampusObservations
extends RefCounted
## The same positions and facing directions drive the exhibit meshes, HUD and authority.
## Indoor anchors are walkable tiles on the visitor's side of the mounted object.
const INDOORS := {
	"teach1": [51, 16, "n", "paper", "换座申请", "换座申请上写着「窗缝漏风，想往里挪一排」。班主任批了个「准」。我对了对走廊里的座次表，申请人的照片还贴在窗边那一格。"],
	"teach2": [21, 12, "w", "tape", "朗读录音", "朗读示范带的盒底写着「第四节，课前留样」。读到第三句有人咳了一声。把带子倒回去，那声咳嗽还夹在同两个字之间。"],
	"teach3": [38, 16, "n", "paper", "订正栏", "一道错题旁边，红笔把三个解法分三栏抄好。每栏末尾都有同一滴墨水，连溅出去的小点都对得上。"],
	"teach4": [45, 9, "w", "height", "窗边身高线", "五月那根身高线量到了我的眉毛。下面贴着全班合照，照片里这道粉笔线也刚画到一半。有人把没拍进照片的那截留白了。"],
	"teach5": [14, 16, "n", "clock", "停用的考场钟", "摘下来的旧考场钟停在十一点四十。玻璃上贴着维修条，写着「取景时已停走」。走廊里的预备铃倒是准点响。"],
	"teach6": [5, 1, "n", "ruler", "日影描线", "女儿墙上描着一次午间测量的日影。粉笔末被风吹跑了，线末压着的小石头还在。有人在日期旁留了一格，等下一次测量。"],
	"admin1": [4, 17, "n", "paper", "借教室回执", "盖了校章的回执写着「第四节借用教室做疏散演练」。小字要求学生原位就坐，老师留在教室清点人数。楼下集合地点一栏划掉了。"],
	"admin2": [32, 15, "e", "tape", "试音带", "带盒上分开记了两次试音。短铃一栏写着「试员举手」。长铃一栏换了笔迹，「人从课桌上抬起头，说刚才听见了」。落款是当班老师。"],
	"admin3": [3, 17, "n", "paper", "门禁勘误", "办事员把相同学号的两张证件照钉在一起。一张戴眼镜，一张没戴。退件理由是「请选择本次演练采用的学期」。"],
	"admin4": [40, 15, "e", "clock", "值班室留样钟", "旧钟停在十一点四十。下面钉了两份值班表，一份按节次填，一份让守在教室的老师用自己的手表记时。第二份只有空格。"],
	"admin5": [47, 17, "n", "paper", "试卷交接单", "交接单附着一张旧收据。原先填的是「空白样卷一份，送档案室」。有人用蓝笔改成「夹回高二（二）班待发试卷」，签名是张九虎。备注仍写「存样编号 K-17」。复印戳旁有一道缺口，和我试卷姓名栏右侧那一截断线正好对上。"],
	"lab1": [1, 9, "w", "tray", "第四节纸样", "透明夹里并排放着甲、乙两张纸。背板上印着「第四节用」，两个格子共用一根只能按一次的打孔杆。"],
	"lab2": [11, 9, "w", "height", "量筒校准尺", "器材员把棚拍用的水面刻度抄在尺上。三张量筒照片里的水一样高，读数旁都画着一颗气泡，正好压住半格。"],
	"lab3": [35, 16, "n", "paper", "机房接线图", "画着教学楼、操场和宿舍的线都接回同一组机柜。另一张纸只有两只方框，一只写「本次纸样」，一只写「北门岗亭」。两张图各有自己的开关。"],
	"lab4": [20, 9, "w", "ruler", "地形拼片", "测绘组把操场外沿描到了刻度尺上。围墙外的一小截街道没有高程数字，只有一张从校门口拍的街景。"],
	"lab5": [29, 9, "w", "tape", "琴房试奏带", "盒上记着演奏者少按了最后一个音。录音里，尾音过后有人在琴凳上挪了半步，木头吱呀一声。再听一遍，还是那半步。"],
	"dorm1": [9, 7, "n", "paper", "宿管交接簿", "阿姨把昨晚没收的三只闹钟一一画在簿上。页脚说今早让失主来认领。三个签名格一直空着。"],
	"dorm2": [13, 4, "e", "ruler", "门背晾衣尺", "有人在尺旁记下衬衣从湿到干用了多久。最后一行的水渍只晕开半圈，像纸被收走时笔尖还沾着水。"],
	"dorm3": [16, 7, "n", "clock", "拆下的闹钟", "这只停了的闹钟也指着十一点四十。电池槽里压着拍摄清单，「拍完放回二号床」。闹钟还在走廊的架子上。"],
	"dorm4": [23, 7, "n", "paper", "失物招领", "值日生把一把蓝伞描在招领纸上。伞尖碰掉了纸角，还留着一点铁锈。下面有人铅笔留言问「看见伞的人，有没有看见我的名字？」"],
	"dorm5": [27, 4, "e", "tape", "熄灯录音", "宿管录下熄灯后的水管响，好给维修师傅听。带盒上写「第三声是隔壁同学碰了床架」。那声响比前两声轻得多。"],
	"dorm6": [30, 7, "n", "paper", "寄存单", "柜里那床没拆封的被子是给新生留的。寄存单上换过三次寝室号，塑料封口和被角那一道折痕却完全重合。"],
	"canteen1": [8, 1, "n", "clock", "窗口试餐钟", "摆样餐时用的钟停在十一点四十。菜单上记着拍照那天葱花切多了，汤面角落漂着一小撮。今天碗里也有那一撮。"],
	"guard1": [1, 6, "w", "paper", "值班员的领物条", "值班员领过两个玻璃盒。八月那只封条上有拆开的笔迹，第四节用的那只另起一行。备注写着「课后凭纸样编号来找我」。"],
	"gear1": [1, 5, "w", "ruler", "球架量规", "架边的量规旁用胶带粘着一张瘪球照片，日期是开学前。体育委员在背后写「借球先捏一捏，照片上试不出来」。"],
	"garage1": [17, 24, "s", "paper", "车位交班图", "夜班保安在油印图上给一辆车换了车位。旧图上几排车都一样，新位置是他当时数过立柱，亲手补上去的。"],
	"bell1": [1, 17, "w", "tape", "钟声采样", "带子上收进了钟声，也收进了敲钟人下楼时钥匙撞扶手的声音。盒背特地圈了第一下，写着「录钟从这里起」。"],
	"trash1": [1, 10, "w", "paper", "废件袋签", "三袋裁剩的纸边共用一张过磅条。保管员在条上划掉一行，「有编号的纸样退北门，不能随纸边处置」。"],
	"link1": [1, 11, "w", "ruler", "连廊测距线", "靠行政楼的一头涂了零点，尺子一直量到实验楼。栏杆外那扇窗上也有人举着尺，尺上的字面朝我，像两边曾经对着量过。"],
	"link2": [3, 12, "e", "paper", "交接签", "教学楼和实验楼各自在交接签上描了半道裂纹。把两张纸的订孔合上，裂纹才接得起来。"],
	"portal_tunnel": [1, 12, "w", "ruler", "隧道里程尺", "入口那间物理实验室在尺上只占零点。后面的格子没有房间名，试员用指甲一道道数过走回来的步子。"],
}
## Outdoor coordinates are in the printed campus map's units, identical to the gate signs.
const OUTSIDE := {
	"field": [289, 283, "w", "ruler", "跑道丈量桩", "体育老师把起跑线挪过半个鞋印。桩上钉着旧测绘照，照片里那条白线还是歪的。"],
	"courts": [568, 380, "s", "paper", "球场借用夹", "篮球社和羽毛球队在同一张照片上圈了各自的场地。体育委员在照片背面抱怨，晒得睁不开眼的那天下午，全校都在拍照。"],
	"shed": [569, 259, "w", "ruler", "车棚编号尺", "车棚横梁上留着一个废车位的编号。旁边的采集底片里，那辆早就被推走的自行车还锁在架上。"],
	# Offsets from the relocated plots keep these markers by their paths.
	"track": [8, -5, "n", "tape", "接力练习带", "田径队留的起跑口令，枪响前总有人小声问「哪一棒」。录音听得见那句话，名单上却没记说话的人。"],
	"garden": [-5, 32, "e", "height", "花圃水位尺", "园丁在尺上写了去年积水的位置。旁边贴着取景当天的便条，「下雨另拍，晴天这张已经齐了」。"],
	"north": [527, 116, "s", "drawing", "北门接人牌", "有人在接人牌上画了个扎辫子的小姑娘。下面是学生的字，「等家里人来就站在门里，别跑到车道上」。"],
	"west": [224, 640, "e", "paper", "闸机维修联", "旧工单留着钳口的三个试咬印。维修员把毛边朝向一一描了下来，背面写着「验完还要看上联」。"],
	"south": [376, 1376, "n", "paper", "南门集合册", "撤离名单封面印着南门。翻到内页，早、晚两次演练用了不同的带队签名，最后一栏都留给清点队尾的人。"],
}
## The index names a physical landing, starting at the lowest door in this shaft.
const LANDINGS := {
	"stair_teach_w": [1, "两道粉笔杠", "二楼平台上有两道粉笔杠，正对着扶手下面一只老扬声器。盖板缝里夹着一截窄纸，写着「西梯采样」。"],
	"stair_teach_e": [0, "东梯踏步线", "新旧两层防滑漆之间露着一个脚印。漆匠只描了左鞋，照片没拍到的那半级还留着底灰。"],
	"stair_admin": [0, "搬运刻线", "搬档案柜的人把转弯的宽度画在墙上。刻线顶端缺一角，和交接表上那道折痕刚好碰在一起。"],
	"stair_lab": [1, "仪器净高线", "一支铅笔在平台上画出了搬运箱的上沿。箱子运走了，墙上还贴着同一天核过净高的纸签。"],
	"stair_dormN": [0, "夜间巡房线", "宿管在平台上贴了只朝上的箭头。箭头背面是张旧值班表，剪掉的那一角刚好缺了一个人的姓。"],
	"stair_dormS": [1, "旧扶手接缝", "有人用粉笔跨过接缝画了一条直线，两边错开半指。接缝旁写着「二楼从南头补拍」。"],
	"stair_garage": [0, "水位旧刻痕", "地下这一头还留着去年的水位痕。描边用的铅笔线一路上到平台，在门框前停住。"],
}

static func _site(id: String, data: Array, anchor: Vector2, base: float) -> Dictionary:
	var normal: Vector2 = -CampusGeometry.NORMALS[data[2]]
	return {"id": id, "form": data[3], "title": data[4], "text": data[5], "anchor": anchor, "normal": normal, "base": base}


static func sites(world: String, room: Variant, stairs: Array, outside: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == "out":
		for id: String in OUTSIDE:
			var d: Array = OUTSIDE[id]
			var at := Vector2(d[0], d[1])
			if id in ["track", "garden"]:
				for plot: Dictionary in outside["objects"]:
					if plot.id == id:
						at += Vector2(plot.x, plot.y)
						break
			result.append(_site("out." + id, d, CampusGeometry.to_scene(null, at * float(outside["SC"])), 0.0))
	elif room != null and INDOORS.has(world):
		var d: Array = INDOORS[world]
		var face: Vector2 = CampusGeometry.NORMALS[d[2]]
		var tile := CampusGeometry.tile_center(room, d[0], d[1])
		var anchor := CampusGeometry.to_scene(room, tile + face * Vector2(room.tw, room.th) * 0.45)
		result.append(_site(world, d, anchor, 0.0))
	elif LANDINGS.has(world):
		var stair := CampusPortals.stair_config(stairs, world)
		if not stair.is_empty():
			var d: Array = LANDINGS[world]
			result.append(_site(world, [0, 0, "w", "chalk", d[1], d[2]], Vector2(-2.10, -0.24), float(d[0]) * float(stair.rise)))
	return result


static func target(sites_here: Array, world: String, room: Variant, pose: Dictionary, doors: Dictionary) -> Dictionary:
	var p: Array = pose["position"]
	var viewer := Vector2(p[0], p[2])
	var facing := Vector2.from_angle(CampusGeometry.ang_from_yaw(float(pose["yaw"])))
	for site: Dictionary in sites_here:
		var offset: Vector2 = viewer - site.anchor
		var distance := offset.length()
		if distance < 0.12 or distance > 1.65 or offset.dot(site.normal) < distance * 0.48: continue
		if facing.dot(-offset / distance) < 0.91: continue
		var height: float = site.base + (0.89 if world in ["link1", "link2"] else 1.50)
		if absf(float(p[1]) - float(site.base)) > (1.80 if world == "out" else 0.82): continue
		if absf(atan2(height - float(p[1]) - 1.58, distance) - float(pose.get("pitch", 0))) > 0.76: continue
		if INDOORS.has(world):
			var d: Array = INDOORS[world]
			var pos: Vector2 = site.anchor
			if not CampusGeometry.tile_los(room, CampusGeometry.to_world(room, viewer.x, viewer.y), CampusGeometry.to_world(room, pos.x, pos.y), d[0], d[1], doors): continue
		return site
	return {}
