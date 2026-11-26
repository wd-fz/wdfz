class_name EntranceExam
extends FeatureModule
## Personal classroom paper. The host owns the clock and the answer sheet in co-op.
const PER_SUBJECT := 5
const COUNT := 30
const SECONDS := 600
const PERMUTATIONS := 24
static var _subjects: Array = []

# An absent module in a legacy save means the student already woke up.
var phase := "done"
var score := -1
var paper: Array = []
var answers: Array = []
var deadline := 0.0


func module_id() -> StringName:
	return &"school.entrance_exam"


func reset() -> void:
	phase = "done"
	score = -1
	paper = []
	answers = []
	deadline = 0


static func rows(subject: int) -> PackedStringArray:
	if _subjects.is_empty():
		for group: String in EntranceExamBank.BANK:
			_subjects.append(group.split("\n", false))
	return _subjects[subject]


func prepare() -> void:
	reset()
	phase = "waiting"


func start(now: float, rng: RandomNumberGenerator) -> void:
	if phase != "waiting": return
	for subject in EntranceExamBank.SUBJECTS.size():
		var pool := range(rows(subject).size())
		for n in PER_SUBJECT:
			var draw := rng.randi_range(0, pool.size() - 1)
			var row := int(pool.pop_at(draw))
			paper.append(row * PERMUTATIONS + rng.randi_range(0, PERMUTATIONS - 1))
			answers.append(-1)
	deadline = now + SECONDS
	phase = "writing"


## Decode the saved permutation without relying on a future engine's shuffle algorithm.
func option_order(index: int) -> Array:
	var remaining := [0, 1, 2, 3]
	var order := []
	var code := int(paper[index]) % PERMUTATIONS
	for stride: int in [6, 2, 1, 1]:
		order.append(remaining.pop_at(floori(float(code) / stride)))
		code %= stride
	return order


func question(index: int) -> Dictionary:
	var subject := floori(float(index) / PER_SUBJECT)
	var row := floori(float(paper[index]) / PERMUTATIONS)
	var cells := rows(subject)[row].split("|")
	var choices := PackedStringArray()
	for option: int in option_order(index):
		choices.append(cells[option + 1])
	return {"subject": EntranceExamBank.SUBJECTS[subject], "text": cells[0], "choices": choices}


func answer(index: int, option: int, now: float) -> bool:
	if phase != "writing" or now >= deadline or index < 0 or index >= COUNT or option < 0 or option > 3: return false
	answers[index] = option
	return true


func submit() -> bool:
	if phase != "writing": return false
	score = 0
	for i in COUNT:
		if int(answers[i]) == option_order(i).find(0): score += 1
	phase = "graded"
	paper.clear()
	answers.clear()
	deadline = 0
	return true


func wake() -> void:
	if phase == "graded": phase = "done"


func capture() -> Dictionary:
	if phase != "writing": return {"phase": phase, "score": score}
	return {"phase": phase, "score": -1, "paper": paper.duplicate(), "answers": answers.duplicate(), "deadline": deadline}


func validate(data: Dictionary) -> String:
	if data.get("phase") not in ["done", "graded", "writing", "waiting"] or not SaveSchema.is_integer(data.get("score"), -1, COUNT):
		return "考试状态无效"
	if data.phase == "graded" and int(data.score) < 0: return "考试成绩无效"
	if data.phase in ["writing", "waiting"] and int(data.score) != -1: return "试卷尚未评分"
	if data.phase != "writing": return ""
	if not SaveSchema.number_in(data.get("deadline"), 1, 1e12): return "考试截止时间无效"
	for key: String in ["paper", "answers"]:
		if not data.get(key) is Array or data[key].size() != COUNT: return "答卷长度无效"
	var seen := {}
	for i in COUNT:
		var subject := floori(float(i) / PER_SUBJECT)
		if i % PER_SUBJECT == 0: seen.clear()
		if not SaveSchema.is_integer(data.paper[i], 0, rows(subject).size() * PERMUTATIONS - 1): return "试题编号无效"
		var row := floori(float(data.paper[i]) / PERMUTATIONS)
		if seen.has(row) or not SaveSchema.is_integer(data.answers[i], -1, 3): return "答卷内容无效"
		seen[row] = true
	return ""


func restore(data: Dictionary) -> void:
	phase = data.phase
	score = int(data.score)
	deadline = float(data.get("deadline", 0))
	paper = data.get("paper", []).duplicate()
	answers = data.get("answers", []).duplicate()
