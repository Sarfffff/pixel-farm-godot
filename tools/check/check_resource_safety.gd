extends SceneTree
## B1-04：整批容量、挥斧中满包、动画期间保存、四季破产恢复与14日木石再生。

var _main: Node
var _bag: Inventory
var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[resource_safety] FAIL: " + message)


func _find(id: StringName) -> Node2D:
	for node: Node in _main.get_node("Farm/World").get_children():
		if node.has_method(&"persistence_id") and node.persistence_id() == id and not node.is_queued_for_deletion():
			return node
	return null


func _fill_bag(full: bool) -> void:
	var slots: Array[Dictionary] = []
	for id: StringName in Inventory.TOOL_IDS:
		slots.append({"id": id, "count": 1})
	if full:
		while slots.size() < _bag.slot_count():
			slots.append({"id": &"stone", "count": 99})
	_bag.from_dict({"slots": slots})


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	_bag = _main.get_node("Systems/Inventory")
	_main.get_node("Systems/Time").running = false
	_main.get_node("Systems/Weather").lock(&"sunny")
	var save: Node = _main.get_node("Systems/Save")
	var baseline: Dictionary = save.collect()
	await _check_trees(save)
	save.apply(baseline)
	await process_frame
	await process_frame
	_check_recovery()
	_check_occupied_regrowth()
	save.apply(baseline)
	await process_frame
	await process_frame
	_check_regrowth()
	_main.queue_free()
	await process_frame
	print("[resource_safety] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_trees(save: Node) -> void:
	var tree: Node2D = get_first_node_in_group(&"choppable")
	var id: StringName = tree.persistence_id()
	for hit: int in tree.hits_required - 1:
		_check(tree.chop(Vector2i.DOWN), "nonfinal chop succeeds")
	var field: Node = _main.get_node("Farm/Tiller")
	var energy: Node = _main.get_node("Systems/Stamina")
	var cell := Vector2i((tree.global_position - Vector2(0, 3)) / 16.0)
	field._on_action_started(&"axe", cell)
	_fill_bag(true)
	var before: int = energy.value
	field._on_use_requested(&"axe", cell)
	_check(energy.value == before and tree.hits_remaining == 1 and not tree.is_felled, "bag filling during windup rejects final hit without stamina loss")
	_check(not tree.chop(Vector2i.DOWN) and not tree.blocked_reason().is_empty(), "direct full-bag chop preserves tree with visible reason")
	# 空间只够部分木材也拒绝，不能先拿走一部分。
	_bag._slots[-1] = {&"id": &"wood", &"count": 99 - (tree.hits_required - 1)}
	var wood: int = _bag.count_of(&"wood")
	_check(not tree.chop(Vector2i.DOWN) and _bag.count_of(&"wood") == wood, "partial stack capacity preserves all final yield")
	_fill_bag(false)
	_check(tree.chop(Vector2i.DOWN), "free space allows the final chop")
	_check(_bag.count_of(&"wood") == tree.hits_required and tree.is_felled, "wood and felled state commit at impact before animation completes")
	_check(not tree.chop(Vector2i.DOWN), "falling tree cannot be cleared before stump appears")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	wood = _bag.count_of(&"wood")
	for repeat: int in 3:
		save.apply(snapshot)
		await process_frame
		tree = _find(id)
		_check(tree != null and tree.is_felled and _bag.count_of(&"wood") == wood, "mid-fall snapshot restores stump and exact wood once")
	_fill_bag(true)
	_check(not tree.chop(Vector2i.DOWN) and tree.stump_hits_remaining == 1, "full bag retains stump yield")
	_fill_bag(false)
	_check(tree.chop(Vector2i.DOWN) and _bag.count_of(&"wood") == 1, "stump reward commits synchronously")
	snapshot = JSON.parse_string(JSON.stringify(save.collect()))
	_check(bool(snapshot.world_objects[String(id)].cleared), "cleared stump is already persistent during fade")
	save.apply(snapshot)
	await process_frame
	_check(_find(id) == null and _bag.count_of(&"wood") == 1, "mid-fade load neither resurrects stump nor duplicates reward")


func _check_recovery() -> void:
	var clock: Node = _main.get_node("Systems/Time")
	var wallet: Economy = _main.get_node("Systems/Economy")
	var forage: Node = _main.get_node("Farm/World/Forage")
	var trade: Node = _main.get_node("Systems/Trade")
	for day: int in [1, 29, 57, 85]:
		clock.day = day
		wallet.coins = 0
		_fill_bag(false)
		for index: int in forage.patches.keys(): forage.remove_patch(index)
		forage._last_day = day - 1
		forage._on_day_started(day)
		_check(forage.patches.size() > 0 and forage.patches.size() <= 3, "each season has a capped free regeneration source")
		var count: int = forage.patches.size()
		forage._on_day_started(day)
		_check(forage.patches.size() == count, "same day cannot regenerate extra free income")
		for patch: Node in forage.patches.values(): patch.interact(Vector2i.ZERO)
		_check(trade.sell(&"fiber", _bag.count_of(&"fiber")) > 0 and wallet.coins >= 8, "zero gold and no seeds recover purchase funds in each season")
		if day == 1:
			_check(trade.purchase(&"carrot_seeds", 1) == 1, "free labor funds a real spring seed purchase")


func _check_occupied_regrowth() -> void:
	var forage: Node = _main.get_node("Farm/World/Forage")
	var player: Node2D = _main.get_node("Farm/World/Player")
	var field: Node = _main.get_node("Farm/Tiller")
	for index: int in forage.patches.keys(): forage.remove_patch(index)
	player.global_position = forage.SPOTS[0]
	var day: int = forage._last_day + 1
	forage._on_day_started(day)
	_check(not forage.patches.has(0), "grass never regrows under player")
	player.global_position = Vector2(472, 174)
	forage._on_day_started(day + 1)
	_check(forage.patches.has(0), "blocked spot retries on a later day after player leaves")
	forage.remove_patch(0)
	var cell := Vector2i(forage.SPOTS[0] / 16.0)
	field._on_use_requested(&"hoe", cell)
	_check(field.has_tilled_soil(cell), "actual hoe reserves the former forage cell")
	forage._on_day_started(day + 2)
	_check(not forage.patches.has(0), "regeneration respects cultivated soil through public query")


func _check_regrowth() -> void:
	_fill_bag(false)
	var manager: Node = _main.get_node("Systems/Regions")
	var clock: Node = _main.get_node("Systems/Time")
	var totals: Dictionary = {"wood": 0, "stone": 0}
	for night: int in 14:
		clock.sleep()
		for id: String in manager.ledger.regions["farm"].objects:
			var state: Dictionary = manager.ledger.object(&"farm", id)
			if state.kind not in ["twig", "small_stone"] or int(state.hits) <= 0: continue
			var rule: Dictionary = manager.ledger.rules[state.kind]
			_check(manager.harvest.hit(&"farm", id, StringName(rule.tool)), "free renewable wood/stone remains harvestable")
		for id: String in manager.ledger.regions["farm"].drops.keys():
			var drop: Dictionary = manager.ledger.regions["farm"].drops[id]
			if totals.has(String(drop.item)):
				totals[String(drop.item)] += 1
				_check(manager.harvest.pickup(&"farm", id), "renewed resources reach shared inventory")
	_check(totals.wood >= 7 and totals.stone >= 7, "14 days retain renewable wood and stone independent of original finite props")
