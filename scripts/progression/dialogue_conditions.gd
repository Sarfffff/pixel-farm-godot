extends RefCounted
## B6-01 对话条件纯求值：只读传入的 conditions/facts，不查场景、不改状态、不写档、不发信号。
## conditions 只接受六类键；未知键或类型错一律返回 false 并在 last_rejection 说明原因。

const KNOWN_KEYS: Array[StringName] = [
	&"friendship_min", &"quest_status", &"day_min", &"day_max", &"weather", &"flag",
]

var last_rejection: String = ""


## facts 契约：friendship(int 好感值)、quests(Dictionary 任务状态)、day(int 绝对日)、
## weather(StringName/String)、flags(Array 已读标记或 Dictionary flag->bool)。
## 缺对应事实或类型不符都按未满足处理，绝不静默放行。
func conditions_met(conditions: Dictionary, facts: Dictionary) -> bool:
	last_rejection = ""
	for raw_key: Variant in conditions:
		if not (raw_key is String or raw_key is StringName):
			return _reject("未知对话条件键: %s" % str(raw_key))
		var key: StringName = StringName(raw_key)
		if not KNOWN_KEYS.has(key): return _reject("未知对话条件键: %s" % key)
		if not _matches(key, conditions[raw_key], facts): return false
	return true


func _reject(reason: String) -> bool:
	last_rejection = reason
	return false


func _matches(key: StringName, requirement: Variant, facts: Dictionary) -> bool:
	match key:
		&"friendship_min": return _minimum(requirement, facts.get("friendship", null), key)
		&"day_min": return _minimum(requirement, facts.get("day", null), key)
		&"day_max": return _maximum(requirement, facts.get("day", null), key)
		&"quest_status": return _quests(requirement, facts.get("quests", null))
		&"weather": return _weather(requirement, facts.get("weather", null))
		&"flag": return _flags(requirement, facts.get("flags", null))
	return _reject("未知对话条件键: %s" % key)


func _minimum(requirement: Variant, value: Variant, key: StringName) -> bool:
	if typeof(requirement) != TYPE_INT or typeof(value) != TYPE_INT:
		return _reject("对话条件 %s 需要整数要求与整数事实" % key)
	if int(value) < int(requirement): return _reject("对话条件 %s 未满足" % key)
	return true


func _maximum(requirement: Variant, value: Variant, key: StringName) -> bool:
	if typeof(requirement) != TYPE_INT or typeof(value) != TYPE_INT:
		return _reject("对话条件 %s 需要整数要求与整数事实" % key)
	if int(value) > int(requirement): return _reject("对话条件 %s 未满足" % key)
	return true


func _quests(requirement: Variant, value: Variant) -> bool:
	if not (requirement is Dictionary) or not (value is Dictionary):
		return _reject("对话条件 quest_status 需要任务表与任务状态事实")
	var wanted: Dictionary = requirement
	var raw_statuses: Dictionary = value
	var statuses: Dictionary = {}
	for raw_id: Variant in raw_statuses:
		statuses[String(raw_id)] = raw_statuses[raw_id]
	for raw_id: Variant in wanted:
		if not (raw_id is String or raw_id is StringName):
			return _reject("对话条件 quest_status 的任务标识类型无效")
		var expected: Variant = wanted[raw_id]
		if not (expected is String or expected is StringName):
			return _reject("对话条件 quest_status 的期望状态类型无效")
		var actual: Variant = statuses.get(String(raw_id), null)
		if not (actual is String or actual is StringName):
			return _reject("对话条件 quest_status 的任务状态类型无效")
		if StringName(actual) != StringName(expected): return _reject("对话条件 quest_status 未满足")
	return true


func _weather(requirement: Variant, value: Variant) -> bool:
	if not (value is String or value is StringName):
		return _reject("对话条件 weather 需要天气事实")
	var current: StringName = StringName(value)
	if requirement is String or requirement is StringName:
		if current != StringName(requirement): return _reject("对话条件 weather 未满足")
		return true
	if requirement is Array:
		var allowed: Array = requirement
		for entry: Variant in allowed:
			if not (entry is String or entry is StringName):
				return _reject("对话条件 weather 的候选项类型无效")
		if not allowed.has(current) and not allowed.has(String(current)):
			return _reject("对话条件 weather 未满足")
		return true
	return _reject("对话条件 weather 的类型无效")


func _flags(requirement: Variant, value: Variant) -> bool:
	var wanted: Array[StringName] = []
	if requirement is String or requirement is StringName:
		wanted.append(StringName(requirement))
	elif requirement is Array:
		for entry: Variant in requirement:
			if not (entry is String or entry is StringName):
				return _reject("对话条件 flag 的候选项类型无效")
			wanted.append(StringName(entry))
	else:
		return _reject("对话条件 flag 的类型无效")
	var read: Dictionary = {}
	if value is Array:
		for entry: Variant in value:
			if not (entry is String or entry is StringName):
				return _reject("对话条件 flag 的已读标记类型无效")
			read[String(entry)] = true
	elif value is Dictionary:
		var flags: Dictionary = value
		for raw_key: Variant in flags:
			if typeof(flags[raw_key]) != TYPE_BOOL:
				return _reject("对话条件 flag 的已读标记类型无效")
			if bool(flags[raw_key]): read[String(raw_key)] = true
	else:
		return _reject("对话条件 flag 需要已读标记事实")
	for flag: StringName in wanted:
		if not read.has(String(flag)): return _reject("对话条件 flag 未满足")
	return true
