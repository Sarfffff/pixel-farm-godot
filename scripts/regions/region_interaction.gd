extends Node
## 角色工具端口适配；保留起手锁定、命中帧提交，不把新资源规则塞回耕地脚本。

var manager: Node
var player: CharacterBody2D
var _locked_id: String = ""
var _locked_region: StringName
var _locked_tool: StringName
var _locked_generation: int = -1


func base_cell() -> Vector2i:
	return Vector2i(((player.global_position - manager.region_origin()) / 16.0).floor())


func target_cell() -> Vector2i:
	return base_cell() + player.facing_vector()


func resolve_target(tool: StringName) -> Vector2i:
	if tool == &"interact":
		var drop: String = manager.nearby_drop()
		if not drop.is_empty(): return base_cell()
	var facing: Vector2i = player.facing_vector()
	var offsets: Array[Vector2i] = [facing, facing + Vector2i(facing.y, -facing.x), facing - Vector2i(facing.y, -facing.x), Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for offset: Vector2i in offsets:
		var cell: Vector2i = base_cell() + offset
		var id: String = manager.resource_at(cell)
		if not id.is_empty() and manager.harvest.can_hit(manager.active_region, id, &"" if tool == &"interact" else tool): return cell
	return target_cell()


func can_use(tool: StringName, cell: Vector2i) -> bool:
	var id: String = manager.resource_at(cell)
	if id.is_empty() or not manager.harvest.can_hit(manager.active_region, id, tool): return false
	var state: Dictionary = manager.ledger.object(manager.active_region, id)
	return manager.stamina.can_spend(manager.harvest_cost(manager.ledger.rules[state.kind], tool))


func can_interact(cell: Vector2i) -> bool:
	return not manager.nearby_drop().is_empty() or can_use(&"", cell)


func interact(cell: Vector2i) -> void:
	var drop: String = manager.nearby_drop()
	if not drop.is_empty():
		manager.harvest.pickup(manager.active_region, drop)
	else:
		var id: String = manager.resource_at(cell)
		if not id.is_empty(): manager.harvest.hit(manager.active_region, id, &"")


func lock_target(tool: StringName, cell: Vector2i) -> void:
	_locked_id = manager.resource_at(cell)
	_locked_region = manager.active_region
	_locked_tool = tool
	var state: Dictionary = manager.ledger.object(_locked_region, _locked_id)
	_locked_generation = int(state.get("generation", -1))


func commit(tool: StringName, cell: Vector2i) -> void:
	if _locked_region != manager.active_region or tool != _locked_tool or _locked_id != manager.resource_at(cell): return
	if int(manager.ledger.object(_locked_region, _locked_id).get("generation", -2)) != _locked_generation: return
	var id: String = _locked_id
	clear_lock()
	manager.harvest.hit(manager.active_region, id, tool)


func clear_lock() -> void:
	_locked_id = ""


func has_harvest_target() -> bool:
	return false


func interaction_hint(tool: StringName) -> String:
	var drop: String = manager.nearby_drop()
	if not drop.is_empty(): return "[F] 拾取地面掉落物"
	var id: String = manager.resource_at(resolve_target(tool))
	if id.is_empty():
		if tool in [&"hoe", &"seeds", &"watering_can"]: return "种植照料请回农舍农场 · 路标 [F] 切换区域"
		return "面向资源使用工具 · 植物和散石按 [F] 采集"
	var state: Dictionary = manager.ledger.object(manager.active_region, id)
	var rule: Dictionary = manager.ledger.rules[state.kind]
	var required: String = "[F] 采集" if String(rule.tool).is_empty() else ("斧头" if rule.tool == "axe" else "石镐")
	var cost: int = manager.harvest_cost(rule, tool)
	if not manager.stamina.can_spend(cost): return "体力不足 · 沿路标回农舍休息"
	return "%s · 还需%d次 · 体力%d" % [required, int(state.hits), cost]
