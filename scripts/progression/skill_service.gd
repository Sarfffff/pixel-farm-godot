extends RefCounted
## B3-01：成功劳动提交与能力查询。组合根注入日期和成功凭据，不订阅入包信号。

signal changed
signal level_advanced(skill: StringName, old_level: int, new_level: int)

const State := preload("res://scripts/progression/skill_state.gd")
const DEFINITION_DIR: String = "res://data/skills"

var busy: bool = false
var last_rejection: String = ""
var _state: RefCounted
var _definitions: Array[SkillDefinition] = []
var _actions: Dictionary[StringName, SkillDefinition] = {}
var _day: Callable


## 定义省略时读取 data/skills；重配是新会话初始化，会清空原技能事实。
func configure(current_day: Callable, definitions: Array[SkillDefinition] = []) -> bool:
	if busy or not current_day.is_valid(): return false
	var candidates: Array[SkillDefinition] = definitions.duplicate()
	if candidates.is_empty():
		for file: String in ResourceLoader.list_directory(DEFINITION_DIR):
			if not file.ends_with(".tres"): continue
			var definition := load(DEFINITION_DIR.path_join(file)) as SkillDefinition
			if definition == null: return false
			candidates.append(definition)
	if candidates.is_empty(): return false
	var ids: Dictionary = {}
	var actions: Dictionary[StringName, SkillDefinition] = {}
	var copies: Array[SkillDefinition] = []
	for definition: SkillDefinition in candidates:
		if definition == null or not definition.is_valid() or ids.has(definition.id): return false
		var copy := definition.duplicate(true) as SkillDefinition
		ids[copy.id] = true
		for action: StringName in copy.experience_for:
			if actions.has(action): return false
			actions[action] = copy
		copies.append(copy)
	copies.sort_custom(func(a: SkillDefinition, b: SkillDefinition) -> bool:
		return a.order < b.order if a.order != b.order else String(a.id) < String(b.id))
	var state := State.new()
	state.configure(copies)
	_definitions = copies
	_actions = actions
	_state = state
	_day = current_day
	last_rejection = ""
	return true


func definitions() -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for definition: SkillDefinition in _definitions: result.append(definition.duplicate(true) as SkillDefinition)
	return result


## receipt: {id: 全局稳定劳动ID, day: 当前绝对日}；数量/经验等外来字段不参与计算。
func record_labor(action: StringName, receipt: Dictionary) -> bool:
	if busy: return false
	last_rejection = ""
	if _state == null or not _actions.has(action):
		last_rejection = "不支持的劳动来源"
		return false
	var raw_id: Variant = receipt.get("id", "")
	if typeof(raw_id) != TYPE_STRING and typeof(raw_id) != TYPE_STRING_NAME:
		last_rejection = "劳动凭据ID无效"
		return false
	var id: String = String(raw_id)
	var day: int = State.integer(receipt.get("day"), 0)
	var today: int = _today()
	if not State.valid_receipt_id(id) or day <= 0 or day != today:
		last_rejection = "劳动凭据ID或日期无效"
		return false
	var definition: SkillDefinition = _actions[action]
	busy = true
	var result: Dictionary = _state.grant(definition.id, definition.experience_for[action], id, day)
	if result.is_empty():
		last_rejection = "劳动已计入或技能已满级"
		busy = false
		return false
	# 凭据、经验、即时能力与待展示升级已完整提交，再通知任何观察者。
	changed.emit()
	if int(result.new_level) > int(result.old_level):
		level_advanced.emit(definition.id, int(result.old_level), int(result.new_level))
	busy = false
	return true


func xp_of(id: StringName) -> int:
	return _state.xp_of(id) if _state != null else 0


func level_of(id: StringName) -> int:
	return _state.level_of(id) if _state != null else 0


func effects_of(id: StringName) -> Dictionary:
	for definition: SkillDefinition in _definitions:
		if definition.id == id: return definition.effects_for(level_of(id))
	return {"stamina_reductions": {}, "fishing_wait_scale": 1.0, "fishing_bite_window_bonus": 0.0}


func stamina_cost(action: StringName, base_cost: int) -> int:
	if base_cost <= 0: return 0
	var reduction: int = 0
	for definition: SkillDefinition in _definitions:
		var effects: Dictionary = effects_of(definition.id)
		reduction += int(effects.stamina_reductions.get(action, 0))
	return maxi(1, base_cost - reduction)


func fishing_parameters(wait_min: float, wait_max: float, bite_window: float) -> Dictionary:
	var effects: Dictionary = effects_of(&"fishing")
	var minimum: float = wait_min if is_finite(wait_min) and wait_min > 0.0 else 0.01
	var maximum: float = wait_max if is_finite(wait_max) and wait_max >= minimum else minimum
	var bite: float = bite_window if is_finite(bite_window) and bite_window > 0.0 else 0.01
	return {"wait_min": maxf(0.01, minimum * float(effects.fishing_wait_scale)),
		"wait_max": maxf(0.01, maximum * float(effects.fishing_wait_scale)),
		"bite_window": maxf(0.01, bite + float(effects.fishing_bite_window_bonus))}


func pending_upgrades(day: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state == null: return result
	for row: Dictionary in _state.pending_upgrades(day):
		for definition: SkillDefinition in _definitions:
			if definition.id == StringName(row.skill):
				row["skill_name"] = definition.display_name
				row["description"] = definition.levels[int(row.level) - 1].description
				result.append(row)
				break
	return result


func acknowledge_summary(day: int) -> bool:
	if busy or _state == null or day <= 0 or day > _today(): return false
	busy = true
	var acknowledged: bool = _state.acknowledge_summary(day)
	if acknowledged: changed.emit()
	busy = false
	return acknowledged


func encode() -> Dictionary:
	return _state.encode() if _state != null else {"version": 1, "xp": {}, "receipts": {}, "pending_upgrades": []}


## false 表示拒绝未来版本/过量结构，现有状态保留；恢复从不发 level_advanced。
func restore(data: Dictionary) -> bool:
	if busy or _state == null: return false
	busy = true
	var restored: bool = _state.restore(data)
	if restored:
		last_rejection = ""
		changed.emit()
	else:
		last_rejection = "技能存档版本或结构不受支持"
	busy = false
	return restored


func release() -> void:
	if busy: return
	_state = null
	_definitions.clear()
	_actions.clear()
	_day = Callable()
	last_rejection = ""


func _today() -> int:
	if not _day.is_valid(): return 0
	var day: int = State.integer(_day.call(), 0)
	return day if day > 0 and day <= State.MAX_DAY else 0
