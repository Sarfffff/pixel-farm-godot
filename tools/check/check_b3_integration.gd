extends SceneTree
## B3 正式会话整合：技能劳动凭据、技能能力应用、制作资格、设备放置/仓储与存档往返。
## 只走正式组合根与公开端口，不用替身代替接线。

const CRATE: StringName = &"storage_crate"
const FENCE: StringName = &"wood_fence"

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _skills: RefCounted
var _bag: Inventory
var _save: Node
var _field: Node
var _crafts: RefCounted
var _placement: RefCounted
var _stamina: Node


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[b3_integration] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_skills = _main.skills
	_bag = _main.get_node("Systems/Inventory")
	_save = _main.get_node("Systems/Save")
	_field = _main.get_node("Farm/Tiller")
	_crafts = _main.crafts
	_placement = _main.placement
	_stamina = _main.get_node("Systems/Stamina")
	_main.get_node("Systems/Time").running = false
	_check_wiring()
	await _check_skill_panel()
	_check_harvest_labor()
	await _check_wood_labor()
	_check_skill_levels()
	_check_crafting_gate()
	_check_placement_flow()
	_check_save_roundtrip()
	_check_summary()
	await _check_lifecycle()
	print("[b3_integration] %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_wiring() -> void:
	_check(_skills != null and _main.labor != null, "正式会话持有技能服务与劳动端口")
	_check(_main.get_node_or_null("UI/SkillPanel") != null, "技能面板已加入UI")
	_check(_main.get_node_or_null("UI/PlacementPanel") != null and _main.get_node_or_null("UI/DeviceStoragePanel") != null, "放置与储物箱面板已加入UI")
	_check(_main.get_node_or_null("Farm/World/PlacementPreview") != null, "放置预览已挂到农场")
	_check(_main.get_node_or_null("PlacementInput") != null, "地图选点适配已挂到会话")
	var state: Dictionary = _save.collect()
	_check(state.has("skills") and state.has("devices"), "存档注册了skills与devices分区")
	_check(_field.tool_cost(&"axe") == 8 and _field.tool_cost(&"harvest") == 2, "未升级时工具体力价保持基准")
	_check(_skills.stamina_cost(&"fishing", 4) == 4, "未升级时投竿体力价保持基准")


func _check_skill_panel() -> void:
	_main._toggle_skills()
	await process_frame
	var panel: Control = _main.get_node("UI/SkillPanel")
	_check(panel.visible, "C键打开技能面板")
	_check(panel.modal_coordinator != null, "技能面板已注册模态协调")
	_main._toggle_skills()
	await process_frame
	_check(not panel.visible, "再次按键关闭技能面板")
	_check(not _main.regions.player.input_locked, "关闭技能面板后不残留输入锁")


func _check_harvest_labor() -> void:
	_stamina.refill()
	var cell: Vector2i = _first_plot()
	_check(cell != Vector2i(-9999, -9999), "农场存在可播种的空耕地")
	var before: int = _skills.xp_of(&"agriculture")
	_field.commit_tool_action(&"seeds", cell)
	_check(_field._crops.has(cell), "真实播种生成作物")
	if not _field._crops.has(cell): return
	var crop: Node = _field._crops[cell]
	var item: StringName = crop.harvest_item_id()
	for _index: int in 12:
		if crop.is_mature(): break
		crop.water()
		crop.grow_if_watered()
	_check(crop.is_mature(), "浇水与生长推进到成熟")
	_field.interact(cell)
	_check(_skills.xp_of(&"agriculture") == before + 8, "真实收获一次加一次农业经验")
	_check(_bag.count_of(item) > 0, "收获产物进入唯一库存")
	_field.interact(cell)
	_check(_skills.xp_of(&"agriculture") == before + 8, "同一格再次交互不重复计经验")


func _check_wood_labor() -> void:
	_stamina.refill()
	var tree: Sprite2D = _first_tree()
	_check(tree != null, "农场存在可砍伐的树")
	if tree == null: return
	var cell: Vector2i = _main._map_cell(tree.global_position - Vector2(0, 3))
	var before: int = _skills.xp_of(&"foraging")
	for _index: int in tree.hits_required + 2:
		if tree.is_felled: break
		_field.begin_tool_action(&"axe", cell)
		_field.commit_tool_action(&"axe", cell)
	_check(tree.is_felled, "真实砍伐把树放倒")
	_check(_skills.xp_of(&"foraging") == before + 6, "倒树只计一次砍伐经验")
	# 倒下动画期间树桩不可命中，等表现结束后再清桩。
	await create_timer(0.6).timeout
	_tree_hit(cell)
	_check(_skills.xp_of(&"foraging") == before + 8, "清桩单独追加经验")
	_tree_hit(cell)
	_check(_skills.xp_of(&"foraging") == before + 8, "已清掉的树桩不再计经验")


func _tree_hit(cell: Vector2i) -> void:
	_field.begin_tool_action(&"axe", cell)
	_field.commit_tool_action(&"axe", cell)


func _check_skill_levels() -> void:
	var xp_before: int = _skills.xp_of(&"foraging")
	_bag.add_item(&"wood", 60)
	_check(_skills.xp_of(&"foraging") == xp_before, "物资入包不改变技能经验")
	_check(_bag.count_of(&"wood") >= 60, "测试木材已入包")
	var guard: int = 0
	while _skills.level_of(&"foraging") < 1 and guard < 20:
		_skills.record_labor(&"chop_tree", {"id": "gate_l1_%d" % guard, "day": 1})
		guard += 1
	_check(_skills.level_of(&"foraging") >= 1, "累计真实凭据后采集升到1级")
	_check(_field.tool_cost(&"axe") == 7, "斧头体力即时从8降到7")
	_check(_field.tool_cost(&"hoe") == 4, "未含减免的锄头价格不变")
	guard = 0
	while _skills.level_of(&"foraging") < 2 and guard < 30:
		_skills.record_labor(&"chop_tree", {"id": "gate_l2_%d" % guard, "day": 1})
		guard += 1
	_check(_skills.level_of(&"foraging") >= 2, "继续累计后采集升到2级")
	_check(_field.tool_cost(&"axe") == 6, "斧头体力继续降到6")
	_check(_skills.stamina_cost(&"forage", 2) == 1, "徒手采集体力降到1")
	guard = 0
	while _skills.level_of(&"fishing") < 1 and guard < 10:
		_skills.record_labor(&"catch_fish", {"id": "gate_fish_%d" % guard, "day": 1})
		guard += 1
	_check(_skills.level_of(&"fishing") >= 1, "鱼获凭据把钓鱼升到1级")
	_check(_skills.stamina_cost(&"fishing", 4) == 3, "投竿体力即时从4降到3")
	var params: Dictionary = _skills.fishing_parameters(4.0, 8.0, 2.0)
	_check(is_equal_approx(float(params.bite_window), 2.0), "钓鱼咬钩窗口按当前等级取值")
	_check(not _skills.record_labor(&"chop_tree", {"id": "gate_l1_0", "day": 1}), "同一凭据不能重复计经验")


func _check_crafting_gate() -> void:
	var wood_before: int = _bag.count_of(&"wood")
	var fence: Dictionary = _crafts.preview(FENCE)
	_check(fence.known and fence.available, "采集1级后围栏配方可用")
	var crate: Dictionary = _crafts.preview(CRATE)
	_check(crate.known and crate.available, "采集2级后储物箱配方可用")
	_check(_crafts.limits(CRATE).max_craftable >= 2, "材料足够时上限允许至少两批")
	_check(_crafts.craft(FENCE), "真实扣料制作围栏")
	_check(_bag.count_of(FENCE) >= 1, "围栏进入唯一库存")
	_check(_crafts.craft(CRATE) and _crafts.craft(CRATE), "连续制作两个储物箱")
	_check(_bag.count_of(CRATE) == 2, "两个储物箱都在背包里")
	_check(_bag.count_of(&"wood") <= wood_before - 44, "制作共消耗44木材")


func _check_placement_flow() -> void:
	var owned: int = _bag.count_of(CRATE)
	var water_cell: Vector2i = _first_water_cell()
	var water_check: Dictionary = _placement.preview(CRATE, &"home", water_cell, 0) if water_cell != Vector2i(-9999, -9999) else {}
	_check(not water_check.is_empty() and not bool(water_check.ok) and not String(water_check.get("reason", "")).is_empty(), "水面拒绝放置且给出原因")
	var path_cell: Vector2i = _first_path_cell()
	var path_check: Dictionary = _placement.preview(CRATE, &"home", path_cell, 0) if path_cell != Vector2i(-9999, -9999) else {}
	_check(not path_check.is_empty() and not bool(path_check.ok) and not String(path_check.get("reason", "")).is_empty(), "道路拒绝放置且给出原因")
	var soil_cell: Vector2i = _first_plot()
	var soil_check: Dictionary = _placement.preview(CRATE, &"home", soil_cell, 0)
	_check(not bool(soil_check.ok) and not String(soil_check.get("reason", "")).is_empty(), "耕地拒绝放置且给出原因")
	var cell_a: Vector2i = _free_cell(Vector2i(-9999, -9999))
	_check(cell_a != Vector2i(-9999, -9999), "农场存在可放置草地")
	var id_a: String = _placement.place(CRATE, &"home", cell_a, 0)
	_check(not id_a.is_empty(), "真实放置成功")
	if id_a.is_empty(): return
	_check(_main.devices.node_for(id_a) != null, "放置后设备节点存在")
	_check(_bag.count_of(CRATE) == owned - 1, "放置消耗1个储物箱")
	var cell_b: Vector2i = _free_cell(cell_a)
	var id_b: String = _placement.place(CRATE, &"home", cell_b, 0)
	_check(not id_b.is_empty() and id_b != id_a, "第二个箱子得到不同稳定ID")
	# 空箱才能移动；有内容时必须先清空。
	var cell_c: Vector2i = _free_cell(cell_b)
	_check(_placement.move(id_a, &"home", cell_c, 0), "移动设备成功 · %s · %s→%s" % [String(_placement.last_rejection), cell_a, cell_c])
	var moved: Dictionary = _placement.instance(id_a)
	_check(not moved.is_empty() and Vector2i(int(moved.cell[0]), int(moved.cell[1])) == cell_c, "移动后格子与实例一致")
	_check(_placement.deposit(id_a, &"wood", 5) == 5, "箱子A存入木材")
	_check(_placement.storage_count(id_a, &"wood") == 5, "箱子A读到5木材")
	_check(_placement.storage_count(id_b, &"wood") == 0, "箱子B内容独立")
	_check(not _placement.move(id_a, &"home", cell_b, 0), "非空箱子拒绝移动")
	_check(not _placement.dismantle(id_a), "非空箱子拒绝拆除")
	_check(_placement.withdraw(id_a, &"wood", 5) == 5, "取回全部木材")
	_check(_placement.dismantle(id_a) and _placement.instance(id_a).is_empty(), "清空后可拆除且实例移除")
	_check(_main.devices.node_for(id_a) == null, "拆除后设备节点移除")
	_check(_placement.dismantle(id_b), "第二个箱子也可拆除")
	_check(_bag.count_of(CRATE) == owned, "拆除返还等量设备物品")


func _check_save_roundtrip() -> void:
	var state: Dictionary = _save.collect().duplicate(true)
	var xp: int = _skills.xp_of(&"foraging")
	var wood: int = _bag.count_of(&"wood")
	var skills_state: Dictionary = state.get("skills", {})
	var receipts: Dictionary = skills_state.get("receipts", {})
	for _index: int in 3:
		_save.apply(state.duplicate(true))
		_check(_skills.xp_of(&"foraging") == xp, "第%d次恢复后经验一致" % (_index + 1))
	_check(_skills.xp_of(&"foraging") == xp, "恢复不追加经验")
	_check(_bag.count_of(&"wood") == wood, "恢复不追加物资")
	_check(_placement.instances().size() == 0, "恢复不复制已拆除的设备")
	var known_receipt: String = String(receipts.keys()[0]) if not receipts.is_empty() else ""
	_check(not known_receipt.is_empty(), "存档保留了劳动凭据")
	if not known_receipt.is_empty():
		_check(not _skills.record_labor(&"chop_tree", {"id": known_receipt, "day": 1}), "读档后旧凭据不能重复计经验")


func _check_summary() -> void:
	var lines: String = String(_main._summary_presenter.snapshot().get("lines", ""))
	_check(lines.contains("技能提升"), "夜间摘要显示真实升级")
	var day: int = int(_main.get_node("Systems/Time").day)
	_check(_skills.acknowledge_summary(day), "关闭摘要后确认已展示")
	lines = String(_main._summary_presenter.snapshot().get("lines", ""))
	_check(not lines.contains("技能提升"), "确认后不再重复提醒")


func _check_lifecycle() -> void:
	var presenter: Node = _main._skill_presenter
	_main.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(_main), "正式会话完整退出")
	_check(not is_instance_valid(presenter), "技能Presenter随组合根销毁")


func _first_plot() -> Vector2i:
	for cell: Vector2i in _field._soil_state.keys():
		if not _field._crops.has(cell):
			return cell
	return Vector2i(-9999, -9999)


func _first_tree() -> Sprite2D:
	var world: Node = _main.get_node("Farm/World")
	for node: Node in get_nodes_in_group(&"choppable"):
		var tree := node as Sprite2D
		if tree == null or tree.get_parent() != world: continue
		if tree.is_felled or bool(tree.get_meta(&"cleared", false)): continue
		return tree
	return null


func _first_water_cell() -> Vector2i:
	var water: TileMapLayer = _main.get_node("Farm/Water")
	for cell: Vector2i in water.get_used_cells():
		return cell
	return Vector2i(-9999, -9999)


func _first_path_cell() -> Vector2i:
	var paths: TileMapLayer = _main.get_node("Farm/Paths")
	for cell: Vector2i in paths.get_used_cells():
		return cell
	return Vector2i(-9999, -9999)


## 找一块真实可放置的草地；这里直接问地图端口，不受背包里还剩几件设备影响。
func _free_cell(avoid: Vector2i) -> Vector2i:
	for y: int in range(4, 27):
		for x: int in range(16, 35):
			var cell := Vector2i(x, y)
			if avoid != Vector2i(-9999, -9999) and (cell - avoid).length_squared() < 9: continue
			var cells: Array[Vector2i] = [cell]
			if bool(_main._placement_query(&"home", cells, "", false).get("ok", false)): return cell
	return Vector2i(-9999, -9999)
