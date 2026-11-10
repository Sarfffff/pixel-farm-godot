extends RefCounted
## B4-02 木匠修路/区域解锁链：纯状态，不读场景/背包/存档，不发信号，不发奖励，不创建节点。
## 调用顺序由主线程负责：requirements_met → 扣料 → advance；本服务只按调用推进一级，不复核库存。

const SAVE_VERSION: int = 1

## 规范化后的阶段副本：{"label": String, "cost": Dictionary[StringName, int], "unlock_region": StringName}
var _stages: Array[Dictionary] = []
var _stage: int = 0


## 新会话初始化：校验通过才整体替换并把阶段归零；非法配置返回 false 并保留原状态。
func configure(definition: RegionUnlockData) -> bool:
	if definition == null or not definition.is_valid(): return false
	var stages: Array[Dictionary] = []
	for row: Dictionary in definition.stages:
		var raw: Dictionary = row.get("cost", {})
		var cost: Dictionary[StringName, int] = {}
		for item: Variant in raw: cost[StringName(item)] = int(raw[item])
		stages.append({
			"label": String(row.get("label", "")),
			"cost": cost,
			"unlock_region": StringName(row.get("unlock_region", &"")),
		})
	_stages = stages
	_stage = 0
	return true


func stage() -> int:
	return _stage


## 当前阶段需要主线程确认并扣除的材料；末阶段返回空（没有下一段可推进）。
func requirement() -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if _stage >= _stages.size() - 1: return result
	var cost: Dictionary[StringName, int] = _stages[_stage].cost
	for item: StringName in cost: result[item] = cost[item]
	return result


## 只按数量比较，不查库存；末阶段没有待确认需求，返回 false。
func requirements_met(have: Dictionary[StringName, int]) -> bool:
	var needed: Dictionary[StringName, int] = requirement()
	if needed.is_empty(): return false
	for item: StringName in needed:
		if int(have.get(item, 0)) < needed[item]: return false
	return true


## 每次调用最多推进一级；末阶段重复调用返回 false 且阶段不变。调用前必须已由主线程确认并扣料。
func advance() -> bool:
	if _stage >= _stages.size() - 1: return false
	_stage += 1
	return true


## 已达成阶段解锁的区域，按阶段顺序去重；不含尚未到达的阶段。
func unlocked_regions() -> Array[StringName]:
	var result: Array[StringName] = []
	if _stages.is_empty(): return result
	for index: int in range(0, mini(_stage, _stages.size() - 1) + 1):
		var region: StringName = StringName(_stages[index].get("unlock_region", &""))
		if region != &"" and not result.has(region): result.append(region)
	return result


func encode() -> Dictionary:
	return {"schema": SAVE_VERSION, "stage": _stage}


## 空字典是旧档缺分区（回到 0 阶段）；未来版本、缺字段或过量结构整分区拒绝并保留现状态。
func restore(data: Dictionary) -> bool:
	if _stages.is_empty(): return false
	if data.is_empty():
		_stage = 0
		return true
	if data.size() > 2: return false
	var schema: Variant = data.get("schema", null)
	if typeof(schema) != TYPE_INT or int(schema) != SAVE_VERSION: return false
	var raw_stage: Variant = data.get("stage", null)
	if typeof(raw_stage) != TYPE_INT: return false
	var restored: int = int(raw_stage)
	if restored < 0 or restored >= _stages.size(): return false
	_stage = restored
	return true


func release() -> void:
	_stages.clear()
	_stage = 0
