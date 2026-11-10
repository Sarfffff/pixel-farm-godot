class_name RegionUnlockData
extends Resource
## 修路/区域解锁链的唯一配置：第 i 段的材料门槛与达成后解锁的区域。
## 约定第 0 段是“未修”，最后一段无材料需求，只提供解锁区域。

const MAX_STAGES: int = 8
const MAX_COST_KINDS: int = 8
const MAX_ITEM_AMOUNT: int = 9999
const MAX_ID_LENGTH: int = 64

@export var id: StringName = &""
## 每段 {"label": String, "cost": {物品ID: 数量}, "unlock_region": StringName}
@export var stages: Array[Dictionary] = []


func is_valid() -> bool:
	if not valid_id(id) or stages.is_empty() or stages.size() > MAX_STAGES: return false
	for index: int in stages.size():
		var row: Dictionary = stages[index]
		if String(row.get("label", "")).strip_edges().is_empty(): return false
		var region: Variant = row.get("unlock_region", &"")
		if not (region is String or region is StringName): return false
		if not String(region).is_empty() and not valid_id(region): return false
		var cost: Variant = row.get("cost", {})
		if not (cost is Dictionary): return false
		var amounts: Dictionary = cost
		if index == stages.size() - 1:
			if not amounts.is_empty(): return false
			continue
		if amounts.size() > MAX_COST_KINDS: return false
		for item: Variant in amounts:
			if not valid_id(item): return false
			var amount: Variant = amounts[item]
			if typeof(amount) != TYPE_INT or int(amount) <= 0 or int(amount) > MAX_ITEM_AMOUNT: return false
	return true


## 物品ID与区域ID共用的小写蛇形格式；只校验格式，不猜物品是否存在（本模块不读库存/物品目录）。
static func valid_id(value: Variant) -> bool:
	if not (value is String or value is StringName): return false
	var text: String = String(value)
	if text.is_empty() or text.length() > MAX_ID_LENGTH or text != text.strip_edges(): return false
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		var lower: bool = code >= 97 and code <= 122
		var digit: bool = code >= 48 and code <= 57
		if not (lower or digit or code == 95): return false
	return true
