class_name PlayerStateModule
extends FeatureModule
## Initial state and bounded commands from the Web rules. Hazard systems come later.

const ID := &"player.vitals"
var _san := 100.0
var _violation := 0.0
var _assimilation := 0.0
var _stamina := 100.0


func module_id() -> StringName:
	return ID


func stamina_max() -> float:
	return 40.0 + 0.6 * _san


func change_san(amount: float) -> void:
	if is_finite(amount):
		_san = clampf(_san + amount, 0.0, 100.0)
		_stamina = minf(_stamina, stamina_max())


func change_violation(amount: float, exempt: bool = false, inspection: bool = false) -> void:
	if not is_finite(amount) or (amount > 0 and exempt and not inspection):
		return
	_violation = clampf(_violation + amount, 0.0, 100.0)


func change_assimilation(amount: float) -> void:
	if is_finite(amount):
		_assimilation = clampf(_assimilation + amount, 0.0, 100.0)


func change_stamina(amount: float) -> void:
	if is_finite(amount):
		_stamina = clampf(_stamina + amount, 0.0, stamina_max())


func capture() -> Dictionary:
	return {"san": _san, "violation": _violation, "assimilation": _assimilation, "stamina": _stamina}


func validate(data: Dictionary) -> String:
	for field: String in ["san", "violation", "assimilation", "stamina"]:
		if not SaveSchema.number_in(data.get(field), 0, 100):
			return "玩家数值无效：%s" % field
	if float(data["stamina"]) > 40.0 + 0.6 * float(data["san"]) + 0.000001:
		return "体力超过当前 SAN 对应上限"
	return ""


func restore(data: Dictionary) -> void:
	_san = float(data["san"])
	_violation = float(data["violation"])
	_assimilation = float(data["assimilation"])
	_stamina = float(data["stamina"])


func reset() -> void:
	_san = 100.0
	_violation = 0.0
	_assimilation = 0.0
	_stamina = 100.0
