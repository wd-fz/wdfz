# 功能模块

每个功能使用独立目录：

| 目录 | 职责 |
| --- | --- |
| `demo/` | 告示牌示例，保留旧测试场景与存档 |
| `campus/` | 正式校园规则：房门、出入口、设施、传送门路线、校园怪谈、粉笔记号（场景适配器在 `game/presentation/world/campus/`） |
| `school/` | 时间与课表、SAN／违规／同化／体力、学生会检查、特殊日与课桌、同学、低 SAN 感官反馈 |
| `items/` | 背包与物品效果 |
| `patrol/` | 巡察者 |
| `anomaly/` | 异象调度与规则 |
| `story/` | 死亡、结局路线、天赋、假正常、广播、国际交流、窗内视线、纸飞机、死亡档案 |
| `garage/` | 车库黑影与开车 |
| `phone/` | 手机网络与机房终端 |
| `body/` | 翻越、受伤与医务室 |
| `progress/` | 成就与速通 |

规则继承 [FeatureModule](../core/modules/feature_module.gd)，在 [SessionFactory.create](../app/session_factory.gd) 注册。模块 ID 和交互 ID 使用稳定命名空间，不从场景路径或中文显示名推导。

本目录只放规则对象与纯数据算法。表现脚本和场景放在 `game/presentation/`，文件读写放在 `game/infrastructure/`。逻辑状态只由规则拥有，表现可以销毁、重建或暂时缺席。

新功能的完整接入步骤、协议和旧版映射见[移植接入指南](../../docs/移植接入指南.md)。
