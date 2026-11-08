extends RefCounted
## 唯一技能事实：经验、已计入劳动 ID、尚未展示的升级。无场景/库存/保存依赖。

const SAVE_VERSION: int = 1
const MAX_DAY: int = 1000000
const MAX_RECEIPT_LENGTH: int = 180

var _definitions: Dictionary[StringName, SkillDefinition] = {}
var _xp: Dictionary[StringName, int] = {}
var _receipts: Dictionary[String, int] = {}
var _pending: Array[Dictionary] = []


func configure(definitions: Array[SkillDefinition]) -> void:
	_definitions.clear()
	_xp.clear()
	_receipts.clear()
	_pending.clear()
	for definition: SkillDefinition in definitions:
		_definitions[definition.id] = definition
		_xp[definition.id] = 0


func xp_of(id: StringName) -> int:
	return int(_xp.get(id, 0))


func level_of(id: StringName) -> int:
	var definition: SkillDefinition = _definitions.get(id)
	return definition.level_for(xp_of(id)) if definition != null else 0


func has_receipt(id: String) -> bool:
	return _receipts.has(id)


## 上层已校验真实来源与日期；仍在模型内判重和封顶，不通知半笔状态。
func grant(skill: StringName, points: int, receipt_id: String, day: int) -> Dictionary:
	var definition: SkillDefinition = _definitions.get(skill)
	if definition == null or points <= 0 or not valid_receipt_id(receipt_id) or day <= 0 or day > MAX_DAY: return {}
	if has_receipt(receipt_id) or xp_of(skill) >= definition.max_xp(): return {}
	var old_level: int = level_of(skill)
	var next_xp: int = mini(definition.max_xp(), xp_of(skill) + points)
	var next_level: int = definition.level_for(next_xp)
	_xp[skill] = next_xp
	_receipts[receipt_id] = day
	for level in range(old_level + 1, next_level + 1):
		_pending.append({"skill": String(skill), "level": level, "day": day})
	return {"old_level": old_level, "new_level": next_level}


func pending_upgrades(day: int = 0) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in _pending:
		if day <= 0 or int(row.day) <= day: rows.append(row.duplicate(true))
	return rows


func acknowledge_summary(day: int) -> bool:
	var remaining: Array[Dictionary] = []
	for row: Dictionary in _pending:
		if int(row.day) > day: remaining.append(row)
	if remaining.size() == _pending.size(): return false
	_pending = remaining
	return true


func encode() -> Dictionary:
	var experience: Dictionary = {}
	for id: StringName in _xp: experience[String(id)] = _xp[id]
	return {"version": SAVE_VERSION, "xp": experience, "receipts": _receipts.duplicate(), "pending_upgrades": _pending.duplicate(true)}


## 缺分区 {} 是旧档；未来版本拒绝且保留当前事实，其他内层字段独立校验。
func restore(data: Dictionary) -> bool:
	if integer(data.get("version", SAVE_VERSION), -1) != SAVE_VERSION: return false
	var experience: Dictionary[StringName, int] = {}
	var source: Variant = data.get("xp", {})
	for id: StringName in _definitions:
		var raw: Variant = source.get(String(id), 0) if source is Dictionary else 0
		experience[id] = clampi(integer(raw, 0), 0, _definitions[id].max_xp())
	# 使用稳定配置上限，避免后续调低曲线时拒绝旧档中已合法累计的凭据。
	var receipt_limit: int = _definitions.size() * SkillDefinition.MAX_EXPERIENCE
	var receipts: Dictionary[String, int] = {}
	var saved_receipts: Variant = data.get("receipts", {})
	if saved_receipts is Dictionary:
		if saved_receipts.size() > receipt_limit: return false
		for raw_id: Variant in saved_receipts:
			if typeof(raw_id) != TYPE_STRING and typeof(raw_id) != TYPE_STRING_NAME: continue
			var receipt_id: String = String(raw_id)
			var day: int = integer(saved_receipts[raw_id], 0)
			if valid_receipt_id(receipt_id) and day > 0 and day <= MAX_DAY: receipts[receipt_id] = day
	var pending: Array[Dictionary] = []
	var seen: Dictionary = {}
	var saved_pending: Variant = data.get("pending_upgrades", [])
	if saved_pending is Array:
		if saved_pending.size() > _definitions.size() * SkillDefinition.LEVEL_LIMIT: return false
		for raw: Variant in saved_pending:
			if not raw is Dictionary: continue
			var raw_skill: Variant = raw.get("skill", "")
			if typeof(raw_skill) != TYPE_STRING and typeof(raw_skill) != TYPE_STRING_NAME: continue
			var skill := StringName(raw_skill)
			if not _definitions.has(skill): continue
			var level: int = integer(raw.get("level"), 0)
			var day: int = integer(raw.get("day"), 0)
			if level <= 0 or level > _definitions[skill].level_for(experience[skill]) or day <= 0 or day > MAX_DAY: continue
			var key: String = "%s/%d" % [skill, level]
			if seen.has(key): continue
			seen[key] = true
			pending.append({"skill": String(skill), "level": level, "day": day})
	_xp = experience
	_receipts = receipts
	_pending = pending
	return true


static func valid_receipt_id(id: String) -> bool:
	return not id.is_empty() and id.length() <= MAX_RECEIPT_LENGTH and id == id.strip_edges() and not id.contains("\n") and not id.contains("\r")


static func integer(value: Variant, fallback: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return fallback
	if not is_finite(float(value)) or float(value) != floor(float(value)): return fallback
	if float(value) < -1000000000.0 or float(value) > 1000000000.0: return fallback
	return int(value)
