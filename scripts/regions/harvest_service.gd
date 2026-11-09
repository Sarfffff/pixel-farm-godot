extends RefCounted
## 采集事务：预检工具和体力，产出保留在地面；完整拾取后才从掉落账本移除。
## 体力价格与成功劳动凭据由组合根注入，技能减免不影响本文件的采集规则。

signal acted(region: StringName, id: String, finished: bool)
signal rejected(reason: String)
var ledger: RefCounted
var inventory: Inventory
var spend_stamina: Callable
var current_day: Callable
## (规则工具, 本次工具, 基准价) -> 实际价；未注入按基准价。
var cost_of: Callable
## (技能动作, 全局凭据ID) -> bool；只在资源确实被采空后调用。
var record_labor: Callable


func can_hit(region: StringName, id: String, tool: StringName) -> bool:
	var state: Dictionary = ledger.object(region, id)
	return not state.is_empty() and int(state.hits) > 0 and StringName(ledger.rules[state.kind].tool) == tool


func hit(region: StringName, id: String, tool: StringName) -> bool:
	if not can_hit(region, id, tool): return false
	var state: Dictionary = ledger.object(region, id)
	var rule: Dictionary = ledger.rules[state.kind]
	if not spend_stamina.call(stamina_cost(rule, tool)):
		rejected.emit("体力不足 · 回农舍休息")
		return false
	var result: Dictionary = ledger.damage(region, id, int(current_day.call()))
	var finished: bool = bool(result.finished)
	if finished: _report_labor(region, id, rule)
	acted.emit(region, id, finished)
	return true


func stamina_cost(rule: Dictionary, tool: StringName) -> int:
	var base: int = int(rule.cost)
	if cost_of.is_valid(): return int(cost_of.call(StringName(rule.tool), tool, base))
	return base


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


## 资源已采空、掉落已记账后才上报；同一资源同一再生周期只产生一次经验。
func _report_labor(region: StringName, id: String, rule: Dictionary) -> void:
	if not record_labor.is_valid() or not current_day.is_valid(): return
	var action: StringName = _action_for(String(rule.tool))
	if action == &"": return
	record_labor.call(action, "%s:%s:%s:%d" % [action, region, id, int(current_day.call())])


func _action_for(tool: String) -> StringName:
	match tool:
		"axe": return &"chop_tree"
		"": return &"forage"
	return &""


func clear() -> void:
	ledger = null
	inventory = null
	spend_stamina = Callable()
	current_day = Callable()
	cost_of = Callable()
	record_labor = Callable()
