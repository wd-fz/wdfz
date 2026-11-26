class_name EntranceExamBank
extends RefCounted
## Each row is a prompt, its correct answer, and three distractors. IDs use the
## subject and row, so append new items instead of reordering existing papers.

const SUBJECTS := ["语文", "数学", "英语", "物理", "化学", "生物"]
const BANK := [
"""《劝学》中「青，取之于蓝，而青于蓝」的第二个「于」表示什么？|比较|被动|处所|原因
「客有吹洞箫者」还原为现代汉语语序，哪项恰当？|有吹洞箫的客人|客人听见有人吹箫|有人向客人借箫|有客人被箫声惊动
哪一句中「之」作动词，意为「到……去」？|吾欲之南海|师道之不传也久矣|句读之不知|夫子之谓也
「吾日三省吾身」中「日」在句中作什么成分？|状语|主语|宾语|补语
《师说》中「古之学者必有师」的「学者」最贴近哪个意思？|求学的人|受聘的导师|著名专家|年长之人
「不吾知也」中的宾语是哪一个字？|吾|不|知|也
「盖余所至，比好游者尚不能十一」中的「十一」指什么？|十分之一|十一处|十一次|十有一人
「先破秦入咸阳者王之」中的「王之」如何理解？|使他为王|王的部下|拜见国王|从王命令
「木直中绳」中的「中」如何解释？|符合|中间|射箭|中心
「六国破灭，非兵不利」中的「兵」指什么？|兵器|士兵|战役|军营
哪部作品按年月先后记事，属于编年体？|《左传》|《史记》|《汉书》|《战国策》
《史记》以人物为中心组织全书，属于哪种体例？|纪传体|编年体|国别体|语录体
《诗经》从音乐角度分为哪三类？|风、雅、颂|赋、比、兴|诗、书、礼|序、传、赞
《离骚》的作者是谁？|屈原|陶渊明|白居易|曹植
《琵琶行》中琵琶女与诗人产生共鸣的原因是什么？|同有漂泊失意的经历|都来自江州|曾同台演奏|同时进京赴考
《祝福》中，哪个人物的遭遇贯穿故事？|祥林嫂|闰土|孔乙己|陈士成
《雷雨》中，周朴园与鲁侍萍重逢主要通过什么展开？|人物对话和舞台动作|章回评点|书信往来|作者长篇议论
《边城》的主要故事发生在什么环境？|湘西边地小镇|江南工业城市|北方沙漠驿站|海上商港
《赤壁赋》中与苏轼展开问答的是谁？|客|舟子|歌女|守卒
《归园田居（其一）》中「羁鸟恋旧林」寄托什么感情？|对田园生活的向往|对边塞的向往|对朝廷升迁的期待|对捕鱼生计的担忧
「远处最后一扇窗也闭上了眼睛。」这句话最突出哪种修辞？|拟人|反问|层递|双关
「三次敲门，三次等待，三次把手放下。」三个短语连用主要运用什么？|排比|设问|通感|反语
「那阵笛声细得像一缕银线。」把听觉写成可见之物，属于什么？|通感|反问|顶真|回文
「灯等着人，人等着信，信等着天亮。」上句末词成为下句开头，属于什么？|顶真|拈连|谐音|借代
哪一句用了借代？|几顶草帽正弯腰插秧|稻穗像弯弯的月牙|田埂在暮色里睡去|今天的雨下得真密
小说先写车站空无一人，再写往日送别的喧闹，主要形成什么？|对比|押韵|用典|谐音
小说开头那把少一颗扣子的伞，结尾成了认人的凭据。开头的细节起什么作用？|埋设伏笔|揭开结局|转换叙述人称|直接抒情
哪项描写主要通过动作表现紧张？|他把车票折好，又摊开，又折好|他穿着浅色外套|售票处有两扇窗|他住在桥那边
第一人称限知叙述中，哪项能由叙述者直接确认？|我听见隔壁的脚步停了|隔壁每个人的内心都很安宁|十年前素未谋面者当时的念头|全城所有人同时做了同一个梦
议论文引用研究数据支持论点时，最应交代什么？|数据来源及适用范围|作者的衣着|排版字号|标题字数
由三个班的问卷断言全省学生都偏爱晨读，最明显的问题是什么？|样本不足以代表总体|缺少比喻|没有押韵|题目太短
哪项最能削弱「这条街只要开夜灯，客流就会增加」这一说法？|多次开灯后，同期同条件客流均未增加|夜灯采用暖色|街边有长椅|有人喜欢夜景
通知要求「参会者最迟周五交稿」。哪一种行为符合要求？|周四提交|下周一提交|周六提交|周日提交
哪句话没有语义重复？|他把两次测量的数据列成表格|大家共同一致赞成|这份报告涉及到达三个方面的问题之所在|其原因是由于设备老化造成的
哪项宜用在给老师的信中，表示请对方修改自己的习作？|敬请指正|望我笑纳|容我惠存|由我垂询
「令尊」一词用来称呼谁？|对方的父亲|自己的父亲|对方的儿子|自己的老师
正式邀请函中哪一句措辞得体？|敬请拨冗出席|你务必给我到场|请把我惠临|我一定赏光贵校
哪一个词语书写正确？|一筹莫展|一愁莫展|一筹末展|一筹莫辗
哪一个成语适合描写各有独到长处、难分高下的两篇文章？|各有千秋|如出一辙|不刊之论|一蹴而就
哪一个成语专指前人没有做过的事业或成就？|前所未有|循规蹈矩|故步自封|因循守旧
论文引用整本书的名称，通常应使用什么标点？|书名号|引号|括号|间隔号
哪一项宜用顿号分隔？|并列的简短词语|完整的反问句|引语的起止|作者的补充说明
「是现在走，还是明早走？」这是哪类问句？|选择问|反问|设问自答|否定陈述
绝句通常有多少句？|四句|六句|八句|十句
律诗的颔联通常指哪两句？|第三、四句|第一、二句|第五、六句|第七、八句
「无边落木萧萧下，不尽长江滚滚来」最明显的句式特点是什么？|对仗|反问|倒装设问|散句独白
「山回路转不见君，雪上空留马行处」主要借什么表达送别之情？|人去后留下的马蹄印|宴会上的劝酒词|城外的战鼓|家书中的叮嘱
「明月松间照，清泉石上流」由哪些景物构成画面？|月、松、泉、石|月、柳、舟、桥|日、松、云、鹤|泉、竹、雁、沙
读人物传记，区分史实与推测最可靠的方法是什么？|查证材料来源并留意推测性措辞|只看篇幅|看人物名字有几个字|依据章节编号
将人物晚年放在开头，随后回到童年按时间讲述，整体属于哪种叙述安排？|倒叙|平叙|纯顺叙|戏剧独白""",
"""设 A={1,3,5}，B={3,4,5}，A 与 B 的交集是什么？|{3,5}|{1,4}|{1,3,4,5}|{5}
不等式 x²−3x+2＜0 的解集是什么？|(1,2)|[1,2]|(−∞,1)|(2,+∞)
函数 y=√(2x−6) 的定义域是什么？|x≥3|x≤3|x＞0|全体实数
f(x)=2x−1，f(f(2)) 等于多少？|5|3|7|9
函数 y=(x+2)²−3 的对称轴在哪里？|x=−2|x=2|y=−3|x=−3
下列函数在全体实数上是奇函数的是哪个？|y=x³+x|y=x²+1|y=2ˣ|y=cos x
log₃81 等于多少？|4|3|9|27
若 2ˣ=1/8，则 x 等于多少？|−3|3|−4|1/3
在区间 [−1,2] 上，f(x)=x² 的最大值是多少？|4|2|1|0
f(x)=x³−3x 在 x=2 处的导数是多少？|9|12|3|6
曲线 y=x² 在 (1,1) 处的切线方程是什么？|y=2x−1|y=x|y=2x+1|y=x−1
若 f′(x) 在区间内恒小于零，则 f 在该区间如何变化？|严格递减|严格递增|恒定|先增后减
方程 x²−6x+5=0 的两根之和是多少？|6|5|−6|−5
等差数列首项 4、公差 −2，第七项是多少？|−8|−10|8|−6
等差数列 1,4,7,… 的前十项和是多少？|145|140|150|155
等比数列首项 3、公比 2，第五项是多少？|48|24|96|32
数列 1,1/2,1/4,1/8 的这四项之和是多少？|15/8|7/4|9/8|2
弧度 π/3 对应多少度？|60°|30°|90°|120°
sin(π/6)+cos(π/3) 等于多少？|1|0|√3|1/2
函数 y=sin(3x) 的最小正周期是多少？|2π/3|3π|π/3|6π
角 θ 为锐角，cos θ=3/5，则 sin θ 是多少？|4/5|3/4|5/4|2/5
边长为 3 与 4 的两边夹角为 30°，三角形面积是多少？|3|6|12|3√3
三角形两边长为 3 和 5，夹角为 60°，第三边长是多少？|√19|√34|7|√39
向量 (2,−1) 与 (3,4) 的数量积是多少？|2|10|−2|7
向量 (1,2) 与 (k,−1) 垂直，则 k 等于多少？|2|−2|1/2|−1/2
点 A(−1,2) 与 B(3,5) 的距离是多少？|5|7|√7|4
过点 (1,2) 且斜率为 3 的直线方程是什么？|y=3x−1|y=3x+1|y=x+3|y=2x+1
点 (0,0) 到直线 3x+4y−10=0 的距离是多少？|2|5|10|√10
圆 (x−1)²+(y+2)²=9 的圆心在哪？|(1,−2)|(−1,2)|(1,2)|(−1,−2)
椭圆 x²/25+y²/9=1 的焦距（两焦点间距离）是多少？|8|4|10|6
抛物线 y²=8x 的焦点是哪个点？|(2,0)|(4,0)|(0,2)|(−2,0)
双曲线 x²/9−y²/4=1 的渐近线斜率是哪一对？|±2/3|±3/2|±4/9|±1
正方体棱长为 2，其体对角线长是多少？|2√3|2√2|4|√3
圆柱底面半径 2、高 3，体积是多少？|12π|6π|18π|4π
一个球的半径变为原来的 2 倍，体积变为原来的几倍？|8|4|2|6
四人排成一列，有多少种不同的排法？|24|16|12|8
从六本不同的书里选两本，不计顺序，有多少种选法？|15|30|12|36
(x+1)⁴ 展开式中 x² 项的系数是多少？|6|4|8|12
同时掷两枚均匀骰子，点数和为 7 的概率是多少？|1/6|1/12|1/36|7/36
袋中有 3 个红球、2 个蓝球。随机取一球为蓝球的概率是多少？|2/5|3/5|1/2|2/3
随机无放回地从 2 个红球、1 个蓝球中取两球，都为红球的概率是多少？|1/3|2/3|1/2|1/9
独立事件 A、B 的概率分别为 0.4 和 0.5，两者同时发生的概率是多少？|0.2|0.9|0.1|0.45
数据 2,3,3,7,10 的中位数是多少？|3|5|7|2
数据 1,2,3 的总体方差（除以 3）是多少？|2/3|1|2|1/3
若 X 取 0 和 2 的概率分别为 1/4 和 3/4，则 E(X) 是多少？|1.5|1|0.5|2
i 为虚数单位，(1+i)² 等于多少？|2i|2|−2i|1+i
复数 3−4i 的模是多少？|5|7|25|1
命题「所有学生均已到场」的否定是什么？|至少有一名学生未到场|所有学生都未到场|恰有一名学生未到场|只有一名学生到场
若 a、b 为正数且 ab=9，a+b 的最小值是多少？|6|9|3|18
直线 y=x 与抛物线 y=x² 的交点有几个？|2|1|0|3""",
"""By the time we arrived yesterday, the lecture ___ already begun.|had|has|is|will
I have lived here ___ 2021.|since|for|during|until
If I ___ you, I would ask for a second opinion.|were|am|have been|will be
The library, ___ opened last spring, stays open late.|which|who|where|what
The student ___ notebook was found can collect it here.|whose|who|whom|which
This is the room ___ the team first met.|where|which|who|whose
Hardly had we sat down ___ the bell rang.|when|than|while|until
Not only ___ the error, but she also corrected it.|did she notice|she noticed|she did noticing|does she noticed
Neither the coach nor the players ___ ready yesterday.|were|was|is|has been
Each of the letters ___ a different stamp.|has|have|are|were
The number of empty seats ___ smaller every week.|is getting|are getting|have got|were getting
She suggested ___ the diagram before answering.|drawing|to draw|drawn|drew
He promised ___ the missing pages tomorrow.|to bring|bringing|brought|has brought
___ from the tower, the river looks like a ribbon.|Seen|Seeing|Sees|Saw
___ the last bus, I had to walk home.|Having missed|To be missed|Missed by|Been missing
The bags ___ by the door belong to the visitors.（已被放好）|placed|placing|to placing|have placing
You ___ have seen me at school yesterday. I was in another city.|cannot|must|should|need
The road is wet. It ___ have rained, but a street cleaner may have passed.|might|must not|cannot|need not
It is the first time that I ___ such a large telescope.|have used|use yesterday|am use|using
I will call you as soon as the train ___ tomorrow.|arrives|will arrive|arrived|would arrive
We stayed inside ___ it was raining heavily.|because|although|unless|whereas
You can borrow the map ___ you return it today.|provided that|even though|as if|whereas
___ tired she was, she checked every figure.|However|Whatever|Whoever|Whichever
The new hall is twice as wide ___ the old one.|as|than|that|like to
There was ___ little time left that we ran to the gate.|so|such|too|enough
The notice was short enough for everyone ___ it at a glance.|to read|reading|read yesterday|to reading
Which word best completes “The discovery had a lasting ___ on our work”?|effect|affect|effective|effectively
Which word means “able to be trusted”?|reliable|reluctant|remote|rigid
In “The lamps gradually faded”, what does “gradually” mean?|little by little|all at once|by accident|on purpose
In “The result contradicted our prediction”, what did the result do?|showed the prediction was wrong|proved it completely correct|repeated it word for word|hid it from readers
Choose the natural expression for taking care of a younger child.|look after|look down on|look into|look back on
“The match was put off until Sunday.” What happened?|It was postponed.|It ended early.|It was never announced.|It started on Friday.
“The team ran out of paper.” What is true?|No unused paper was left.|Paper was carried outdoors.|The team copied the paper.|The team refused new paper.
Which sentence uses “advice” correctly?|She gave me some advice.|She gave me an advice.|She gave me two advices.|She gave me many advice.
Which sentence correctly asks about duration?|How long did the meeting last?|How often did the meeting last long?|How far time was it?|How many time did it take?
The guide reminded us ___ touch the paintings.|not to|to not touching|don't to|not touching to
I prefer walking ___ taking a crowded bus.|to|than|from|at
The teacher divided the class ___ four groups.|into|among of|with|onto
We were surprised ___ the sudden change.|by|onto|during|towards to
He took an umbrella ___ case the rain returned.|in|on|at|for
“The lift is out of order. Please use the stairs.” Where should visitors go?|To the stairs.|To the roof.|To the lift.|To the exit only.
“A ticket covers one adult and up to two children.” Which group needs just one ticket?|One adult and two children.|Two adults and a child.|Three adults.|One adult and three children.
“The shop closes at six except on Fridays, when it closes at eight.” When can you enter at seven in the evening?|Friday|Monday|Wednesday|Thursday
“Return the book within a week of borrowing it.” What limits the loan?|A seven-day period.|The total number of pages.|The reader's age.|The day the library opened.
“Mia folded the note and tucked it into her pocket.” What does “it” refer to?|The note.|The pocket.|Mia.|The fold in her coat.
“Although the path was steep, everyone reached the top.” What is emphasized?|Success despite difficulty.|Failure caused by rain.|A choice to turn back.|The path was flat.
“Unlike the first trial, the second produced a clear signal.” Which trial gave the clear signal?|The second.|The first only.|Neither.|An unmentioned third trial.
“You needn't print the form.” What does the speaker mean?|Printing is optional.|Printing is forbidden.|Printing is compulsory.|Printing is impossible.
“We regret to inform you that the trip is cancelled.” What is the purpose?|To announce a cancellation.|To request payment.|To praise a trip.|To extend an invitation.
Which closing best suits a formal request to a museum?|Thank you for considering my request.|Give me an answer now!|Whatever, see you.|You owe me a reply.""",
"""物体沿直线从坐标 −2 m 移到 5 m，位移是多少？|+7 m|+3 m|−7 m|−3 m
一名同学绕环形跑道跑一圈回到起点，平均速度的大小是多少？|0|等于平均速率|等于最大速率|等于最小非零速率
速度从 3 m/s 匀加速至 11 m/s 用了 4 s，加速度是多少？|2 m/s²|3.5 m/s²|8 m/s²|0.5 m/s²
速度—时间图像中，曲线和时间轴之间的有向面积表示什么？|位移|加速度|合外力|动量变化率
物体由静止自由下落 3 s，忽略空气阻力，g=10 m/s²，下降多高？|45 m|30 m|90 m|15 m
忽略空气阻力，水平抛出的球在竖直方向做什么运动？|自由落体运动|匀速直线运动|匀速圆周运动|简谐运动
质量 2 kg 的物体受合力 6 N，加速度大小是多少？|3 m/s²|12 m/s²|4 m/s²|1/3 m/s²
在惯性参考系中，合外力为零时，运动物体将如何运动？|保持原有速度|逐渐停下|不断加速|一定转弯
书静止放在水平桌面上，和桌面对书的支持力互为作用力与反作用力的是哪一个？|书对桌面的压力|地球对书的重力|桌子的重力|地面对桌脚的支持力
滑块在粗糙水平地面滑动，法向力 20 N，动摩擦因数 0.25，滑动摩擦力大小是多少？|5 N|80 N|20.25 N|0.0125 N
物体做匀速圆周运动时，向心加速度指向哪里？|圆心|切线前方|半径外侧|切线后方
做圆周运动的物体周期为 0.5 s，频率是多少？|2 Hz|0.5 Hz|π Hz|4π Hz
地球附近同一地点，质量加倍时重力加速度如何变化？|保持不变|加倍|减半|变为四倍
万有引力定律中，距离变为原来两倍，两质点质量不变，引力如何变化？|变为四分之一|变为二分之一|加倍|变为四倍
恒力 10 N 沿位移方向推动箱子 3 m，做功多少？|30 J|3 J|13 J|10/3 J
恒力垂直于运动方向，其瞬时功率是多少？|0|力乘以速率|力除以速率|一定为负
质量 2 kg 的物体速率为 3 m/s，动能是多少？|9 J|6 J|18 J|3 J
质量 1 kg 的书升高 2 m，g=10 m/s²，重力势能增加多少？|20 J|2 J|5 J|10 J
哪种情况下机械能守恒？|只有重力做功的抛体运动|汽车在平路上制动|箱子沿粗糙面减速|物体被电机匀速提升
匀速提升载荷做功 600 J，用时 3 s，平均功率是多少？|200 W|1800 W|603 W|20 W
质量 3 kg 的球以 2 m/s 向东运动，动量为多少？|6 kg·m/s 向东|6 kg·m/s 向西|1.5 kg·m/s 向东|5 kg·m/s 向东
恒定合力 5 N 作用 0.4 s，冲量大小是多少？|2 N·s|12.5 N·s|5.4 N·s|0.08 N·s
两小车碰撞过程中系统合外力可忽略，一定守恒的是哪一项？|总动量|总动能|每辆车的动量|每辆车的速度
质量块在理想弹簧上做简谐运动，经过平衡位置时速率如何？|达到最大|等于零|等于振幅|总在减小
小角度下，单摆摆长变为原来的 4 倍，周期怎样变化？|变为 2 倍|变为 4 倍|变为一半|保持不变
波的频率为 5 Hz，波长 0.8 m，波速是多少？|4 m/s|6.25 m/s|0.16 m/s|5.8 m/s
横波中质点振动方向与波传播方向有什么关系？|垂直|平行同向|平行反向|始终成 45°
声波从空气进入水中时，由声源决定的哪一个量保持不变？|频率|波速|波长|介质密度
真空中的点电荷相距减半而电荷量不变，库仑力大小怎样变化？|变为 4 倍|变为 2 倍|变为一半|变为四分之一
电场方向按照什么规定？|正试探电荷所受电场力的方向|负试探电荷所受电场力的方向|磁针北极指向|电流的反方向
匀强电场沿场线方向前进，电势如何变化？|降低|升高|不变|先升后降
电容器电荷量 6 μC，两端电压 3 V，电容是多少？|2 μF|18 μF|0.5 μF|9 μF
金属导线不变温，长度加倍、截面积不变，电阻怎样变化？|加倍|减半|不变|变为四倍
电阻 12 Ω，端电压 6 V，通过电流是多少？|0.5 A|2 A|72 A|18 A
6 Ω 和 3 Ω 两电阻串联，总电阻是多少？|9 Ω|2 Ω|3 Ω|18 Ω
两个 8 Ω 电阻并联，等效电阻是多少？|4 Ω|16 Ω|8 Ω|64 Ω
电流 2 A 通过 3 Ω 电阻持续 5 s，产生热量多少？|60 J|30 J|12 J|15 J
理想电压表测小灯泡端电压时，应怎样接入？|与灯泡并联|与灯泡串联|与电源断开|直接替换灯泡
带电粒子的速度与匀强磁场平行，仅考虑磁场作用，洛伦兹力大小是多少？|0|qvB 的绝对值|qv 的绝对值|B/v
导体棒垂直磁场且垂直电流，B=0.5 T，I=2 A，棒长 0.4 m，安培力多大？|0.4 N|2.5 N|1.6 N|4 N
哪一变化能在闭合线圈中产生感应电流？|穿过线圈的磁通量发生变化|线圈始终静止在恒定匀强磁场中|仅增加观察者的距离|室内光线变暗且磁通不变
楞次定律中，感应电流的磁场总是阻碍什么？|原磁通量的变化|原磁通量本身|线圈的电阻|所有电荷运动
理想变压器原、副线圈匝数比为 4∶1，原边交流电压 220 V，副边电压多大？|55 V|880 V|110 V|44 V
光从空气斜射入折射率更大的玻璃，折射角与入射角相比如何？|较小|较大|相等|必为零
双缝干涉实验中，其余条件不变，换用波长更长的光，条纹间距怎样变化？|变大|变小|不变|变为零
气体分子的无规则热运动，通常用什么宏观量反映平均动能的高低？|温度|体积|颜色|总质量
一定量理想气体等温压缩到原体积的一半，压强怎样变化？|加倍|减半|不变|变为四倍
气体吸热 50 J，同时对外做功 20 J，内能怎样变化？|增加 30 J|增加 70 J|减少 30 J|减少 70 J
光子频率加倍时，单个光子能量如何变化？|加倍|减半|保持不变|变为四倍
某核素半衰期为 3 天，大量该核素经过 6 天后约剩原来的多少？|1/4|1/2|1/6|1/8""",
"""下列哪一种属于纯净物？|蒸馏水|海水|空气|黄铜
下列哪种变化属于化学变化？|铁生锈|冰熔化|食盐晶体研碎|水蒸气冷凝
溶液和胶体的重要区别在于什么？|分散质粒子大小|容器颜色|是否含水|溶质名称长短
光束穿过树荫中的薄雾，可见光路，这主要体现什么？|丁达尔效应|升华|中和|电解
从泥水中除去不溶泥沙，最合适的方法是什么？|过滤|蒸馏分离同位素|加水稀释|加入指示剂
把食盐水中的大部分水移走并得到晶体，适合利用什么操作？|蒸发结晶|分液|磁选|层析分离色素
分液漏斗适合分离哪一组液体？|水与植物油|水与乙醇|水与食盐水|乙醇与乙醇水溶液
原子序数等于原子的什么数目？|质子数|中子数|质量数|电子层数
同一元素的不同同位素一定有什么共同点？|质子数相同|中子数相同|质量数相同|核子总数相同
质量数为 23、质子数为 11 的原子有多少个中子？|12|11|23|34
钠原子形成 Na⁺ 时发生什么？|失去一个电子|得到一个电子|失去一个质子|得到一个中子
同一主族元素从上往下，原子电子层数怎样变化？|增加|减少|保持不变|先增后减
同一周期主族元素从左到右，原子序数逐个怎样变化？|增加 1|减少 1|保持不变|增加 2
氯原子最外层有多少个电子？|7|1|5|8
下列哪一种物质中含有离子键？|NaCl|H₂|O₂|Cl₂
水分子中氧、氢原子通过什么键结合？|极性共价键|离子键|金属键|分子间氢键
冰熔化时主要改变什么？|分子的排列和分子间作用|氧原子的质子数|水分子的化学组成|氢的原子序数
金刚石和石墨互为什么？|同素异形体|同位素|同系物|同分异构体
1 mol 粒子约含有多少个粒子？|6.02×10²³|6.02×10²⁰|3.01×10²³|1.00×10²³
水的摩尔质量约为 18 g/mol，36 g 水的物质的量是多少？|2 mol|0.5 mol|18 mol|36 mol
0.2 mol 溶质配成 0.5 L 溶液，物质的量浓度是多少？|0.4 mol/L|0.1 mol/L|2.5 mol/L|0.7 mol/L
稀释过程中未损失溶质，保持不变的是哪一项？|溶质物质的量|溶液体积|溶质浓度|溶剂质量
Na₂SO₄ 水溶液中，来自它的 Na⁺ 和 SO₄²⁻ 数目比是多少？|2∶1|1∶2|1∶1|2∶3
配平 Al+O₂→Al₂O₃，最简整数系数依次是什么？|4、3、2|2、1、1|1、2、1|3、2、3
氧化还原反应中，被氧化的元素化合价如何变化？|升高|降低|不变|必定变为零
H₂SO₄ 中硫的化合价是多少？|+6|+4|−2|0
下列哪一个变化中发生了还原？|Cu²⁺ 得到电子生成 Cu|Fe 变成 Fe²⁺|Na 变成 Na⁺|Zn 变成 Zn²⁺
金属锌与硫酸铜溶液反应，溶液中的哪种离子被消耗？|Cu²⁺|Zn²⁺|Na⁺|Cl⁻
酸与碱中和的离子反应 H⁺+OH⁻ 生成什么？|H₂O|H₂|O₂|H₂O₂
常温下 pH=3 与 pH=5 的稀水溶液相比，前者氢离子浓度是多少倍？|100 倍|2 倍|5 倍|1/100 倍
常温下纯水的 pH 约为多少？|7|0|1|14
醋酸在水中仅部分电离，属于什么？|弱电解质|强电解质|非电解质|金属单质
哪种离子遇到含氯离子的水溶液容易形成白色沉淀 AgCl？|Ag⁺|K⁺|Na⁺|NO₃⁻
碳酸钙与稀酸反应产生的气体主要是什么？|二氧化碳|氮气|氢气|氧气
相同条件下，把大块固体反应物磨细，通常使反应加快，主要原因是什么？|接触面积增大|元素种类改变|原子质量变小|反应物变成催化剂
催化剂加快反应速率，通常通过什么方式？|提供活化能较低的反应途径|增大平衡常数|改变总反应焓|增加反应物总量
可逆反应达到化学平衡时，正逆反应速率有何关系？|相等且通常均不为零|全都停止|正反应必快一倍|逆反应停止
在其他条件不变时，升温会使化学平衡向哪个方向移动？|吸热方向|放热方向|气体较少方向|固体较多方向
原电池把哪类能量主要转化为电能？|化学能|声能|核能|重力势能
原电池放电时，负极发生什么反应？|氧化反应|还原反应|一定是中和反应|一定是沉淀反应
下列哪一个是烷烃？|乙烷|乙烯|乙炔|乙醇
乙烯分子中两个碳原子之间是什么键？|双键|单键|三键|离子键
乙醇的官能团是什么？|羟基|羧基|醛基|酯基
乙酸分子中决定其酸性的官能团是什么？|羧基|羟甲基|碳碳双键|醚键
分子式相同但结构不同的化合物互称什么？|同分异构体|同位素|同素异形体|同一种分子
聚乙烯的单体是什么？|乙烯|乙烷|乙醇|乙酸
淀粉遇碘液显什么特征颜色？|蓝色|橙红色|亮黄色|无色
向硬水中加适量肥皂难以起泡，主要与哪些离子有关？|钙离子和镁离子|钠离子和钾离子|氯离子和硝酸根|氢离子和氦原子
铝合金与纯铝相比用作结构材料的常见优势是什么？|强度可提高|一定完全不导电|一定透明|原子序数改变
在垃圾分类中回收铝罐主要能带来什么效益？|减少新铝冶炼所需资源与能耗|使铝变为可再生元素|使铝的原子量下降|完全消除所有运输能耗""",
"""细胞膜的基本骨架是什么？|磷脂双分子层|纤维素层|蛋白质双层|核酸单层
细胞内合成蛋白质的直接场所是哪里？|核糖体|溶酶体|中心体|液泡
真核细胞进行有氧呼吸的主要细胞器是什么？|线粒体|高尔基体|中心体|核仁
植物细胞中，光合作用光反应发生在哪里？|叶绿体类囊体薄膜|叶绿体基质|线粒体内膜|细胞核膜
光合作用释放的氧气直接来自什么物质？|水|二氧化碳|葡萄糖|叶绿素
植物光合作用固定二氧化碳的反应主要发生在哪里？|叶绿体基质|液泡|细胞壁|类囊体腔
植物细胞壁的主要组成成分包括哪一组？|纤维素和果胶|磷脂和胆固醇|糖原和脂肪|核酸和蛋白质
控制进出细胞的物质种类，体现了细胞膜的什么特性？|选择透过性|完全封闭性|绝对刚性|遗传稳定性
成熟植物细胞置于较浓的蔗糖溶液中，初期通常发生什么？|细胞失水|细胞吸水膨胀|细胞壁消失|叶绿体变为细胞核
物质逆浓度梯度运输且消耗能量，属于什么？|主动运输|自由扩散|协助扩散|单纯渗透
下列哪一项属于单糖？|葡萄糖|淀粉|糖原|纤维素
动物细胞储存葡萄糖的主要多糖是什么？|糖原|纤维素|淀粉|蔗糖
蛋白质的基本组成单位是什么？|氨基酸|核苷酸|脂肪酸|葡萄糖
两个氨基酸通过什么化学键连接成二肽？|肽键|氢键|磷酸二酯键|碳碳双键
酶具有专一性，意思是什么？|一种酶通常只催化一类或一种反应|所有酶只在胃中起作用|酶使用后立刻消失|每种酶都能催化任意反应
ATP 在细胞中主要承担什么功能？|为生命活动直接供能|长期储存遗传信息|构成细胞壁|携带氧气
有氧呼吸第一阶段，葡萄糖在哪里开始分解？|细胞质基质|细胞核|线粒体内膜|高尔基体
叶片气孔关闭时，首先直接限制哪种气体从外界进入叶片用于光合作用？|二氧化碳|氦气|氢气|氮气
在一定范围内提高光照强度，净光合速率不再上升，说明什么？|其他因素可能成为限制条件|叶片一定死亡|光不再含能量|植物不再呼吸
有丝分裂前，DNA 复制发生在细胞周期的哪个阶段？|分裂间期的 S 期|分裂后期|分裂末期|细胞质分裂之后的任意时刻
有丝分裂后期，姐妹染色单体发生什么变化？|分开并移向两极|两两联会|消失且不形成子染色体|全部留在赤道面
典型减数第一次分裂后期，主要分离的结构是什么？|同源染色体|姐妹染色单体|核糖体两亚基|DNA 双链
人类正常体细胞通常有多少条染色体？|46 条|23 条|44 条|92 对
细胞分化形成不同类型的组织，主要原因是什么？|基因的选择性表达|所有细胞的遗传密码不同|每种组织只剩一个基因|所有细胞核都消失
DNA 的基本组成单位是什么？|脱氧核糖核苷酸|氨基酸|核糖|脂肪酸
DNA 双链中，腺嘌呤通常与哪种碱基配对？|胸腺嘧啶|鸟嘌呤|胞嘧啶|尿嘧啶
RNA 使用而 DNA 通常不使用的碱基是什么？|尿嘧啶|腺嘌呤|鸟嘌呤|胞嘧啶
DNA 半保留复制后，每个子代双链具有什么特点？|一条母链和一条新链|两条链都是母链|两条链都由 RNA 构成|只有一条链
遗传信息从 DNA 转录主要形成什么？|RNA|多肽|多糖|脂质
翻译过程中，直接把氨基酸运到核糖体的是什么？|tRNA|DNA|细胞壁|胆固醇
在完全显性条件下，Aa 与 Aa 杂交，子代隐性表型的理论比例是多少？|1/4|1/2|3/4|1
若某对等位基因遵循分离定律，Aa 个体形成的配子通常是哪两类？|A 和 a|Aa 和 aa|AA 和 Aa|AA 和 aa
衡量种群进化的直接遗传指标是什么？|基因频率改变|个体短期体重改变|个体一生迁移距离|单个细胞暂时失水
自然选择直接作用于个体的什么方面？|可表现出的性状|基因的名称|个体的主观愿望|物种的学名
人体维持内环境稳态所依赖的典型调节方式是什么？|负反馈|无限制正反馈|只进不出|完全不响应变化
血糖升高后，胰岛素分泌增加的主要作用是什么？|促进细胞摄取和利用葡萄糖|促进肝糖原大量分解|直接分解食物纤维素|抑制葡萄糖进入细胞
神经元间常见化学突触中，信号越过突触间隙依赖什么？|神经递质|血红蛋白|纤维素|淀粉
人体反射弧中，将兴奋由感受器传向中枢的是哪一部分？|传入神经|传出神经|效应器|运动终板
人在炎热环境中，哪一反应有利于散热？|汗液蒸发|骨骼肌战栗|皮肤血管持续收缩|竖毛肌紧张
植物幼苗向单侧光弯曲，通常是因为哪一侧伸长更快？|背光侧|向光侧|左右完全一致|根冠侧且茎不伸长
果实成熟时起重要调节作用的植物激素是哪种？|乙烯|赤霉素|细胞分裂素|生长素
某地同一时间生活的全部同种个体称为什么？|种群|群落|生态系统|生物圈
样方法适合估算下列哪一类生物的种群密度？|草地上固定生长的蒲公英|快速飞行的燕子|远洋洄游的鱼群|空中成群迁飞的蝗虫
种群数量的 S 形增长曲线中，K 值代表什么？|环境容纳量|初始种群数量|出生率最大值|死亡率最小值
草→兔→狐这一食物链中，兔属于第几营养级？|第二|第一|第三|第四
生态系统的能量流动通常有什么特点？|单向流动、逐级递减|完全循环、逐级增加|只在生产者间流动|每级都保持等量
生态系统中，分解者的主要作用是什么？|把有机物分解并归还无机环境|用阳光直接合成所有营养|永久封存全部元素|只为顶级消费者供氧
生物多样性通常包括哪三个层次？|遗传、物种、生态系统|个体、组织、器官|光、水、温度|生产、运输、销售
森林火灾后，土壤及部分种子仍保留，随后发生的群落演替属于什么？|次生演替|初生演替|细胞分化|人工选择
对自然保护区的原生湿地实施保护，属于哪类保护？|就地保护|迁地保护|人工驯化|标本保存""",
]
