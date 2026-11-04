extends RefCounted
## 采集事务：预检工具和体力，产出保留在地面；完整拾取后才从掉落账本移除。

signal acted(region: StringName, id: String, finished: bool)
signal rejected(reason: String)
var ledger: RefCounted
var inventory: Inventory
var spend_stamina: Callable
var current_day: Callable


func can_hit(region: StringName, id: String, tool: StringName) -> bool:
	var state: Dictionary = ledger.object(region, id)
	return not state.is_empty() and int(state.hits) > 0 and StringName(ledger.rules[state.kind].tool) == tool


func hit(region: StringName, id: String, tool: StringName) -> bool:
	if not can_hit(region, id, tool): return false
	var state: Dictionary = ledger.object(region, id)
	var rule: Dictionary = ledger.rules[state.kind]
	if not spend_stamina.call(int(rule.cost)):
		rejected.emit("体力不足 · 回农舍休息")
		return false
	var result: Dictionary = ledger.damage(region, id, int(current_day.call()))
	acted.emit(region, id, bool(result.finished))
	return true


func pickup(region: StringName, id: String) -> bool:
	var drop: Dictionary = ledger.regions.get(String(region), {}).get("drops", {}).get(id, {})
	if drop.is_empty(): return false
	var item: StringName = StringName(drop.item)
	var count: int = int(drop.count)
	if inventory.definition(item) == null or not inventory.has_space_for(item, count):
		rejected.emit("背包空间不足 · 掉落物仍留在地面")
		return false
	inventory.begin_update()
	var remaining: int = inventory.add_item(item, count)
	if remaining == 0: ledger.take_drop(region, id)
	inventory.end_update()
	return remaining == 0


func clear() -> void:
	ledger = null
	inventory = null
	spend_stamina = Callable()
	current_day = Callable()
