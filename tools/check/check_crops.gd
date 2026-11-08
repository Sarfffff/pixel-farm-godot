extends SceneTree
## 作物回归：播种消耗种子、浇水推进阶段、成熟提示、收获进背包、满包不丢作物。
## --headless --path . --script res://tools/check/check_crops.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_CELL := Vector2i(18, 6)

var _main: Node2D
var _tiller: Node2D
var _inventory: Inventory
var _failures: int = 0
var _checks: int = 0
var _atomic_end: bool = false
const OTHER_CELL := TEST_CELL + Vector2i(1, 0)


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[crops] FAIL: " + message)


## 构造一次真实按键：keycode 与 physical_keycode 都要填，
## 才会像真键盘那样同时命中绑定在同一物理键上的多个 action。
func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	return event


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load(MAIN_SCENE).instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	# 锁晴天：雨天会自动替玩家浇所有作物，断言"没浇水就不长"会变成随机失败。
	var weather := get_first_node_in_group(&"weather") as Node
	if weather != null:
		weather.call(&"lock", &"sunny")
	await physics_frame
	await physics_frame
	await create_timer(0.2).timeout
	_tiller = _main.get_node("Farm/Tiller") as Node2D
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	_main.get_node("Systems/Time").running = false

	_check(_tiller._crop_definitions.size() >= 2, "crop definitions loaded")
	_check(_tiller._seed_id() == &"carrot_seeds", "first seed in bag is picked")
	var seeds_before: int = _inventory.count_of(&"carrot_seeds")
	_check(_tiller.can_use(&"seeds", TEST_CELL), "tilled cell accepts seeds")
	_check(not _tiller.can_use(&"seeds", Vector2i(16, 5)), "untilled cell rejects seeds")
	_check(not _tiller.can_use(&"watering_can", TEST_CELL), "empty tilled cell rejects water until planted")

	# 播种：扣 1 个种子，格子上出现作物
	_tiller._on_use_requested(&"seeds", TEST_CELL)
	_check(_tiller._crops.has(TEST_CELL), "crop spawned")
	_check(_inventory.count_of(&"carrot_seeds") == seeds_before - 1, "seed consumed")
	var crop: Crop = _tiller._crops[TEST_CELL]
	_check(crop.stage == 0, "crop starts at first stage")
	_check(not _tiller.can_use(&"seeds", TEST_CELL), "occupied cell rejects a second seed")
	_check(not _tiller.can_use(&"hoe", TEST_CELL), "hoe cannot erase a planted cell")

	# 浇水只打标记，生长留到睡觉结算
	_check(_tiller.can_use(&"watering_can", TEST_CELL), "crop accepts water")
	_tiller._on_use_requested(&"watering_can", TEST_CELL)
	_check(crop.watered, "watering marks the crop as watered")
	_check(crop.stage == 0, "watering alone does not advance the stage")
	_check(not _tiller.can_use(&"watering_can", TEST_CELL), "same crop rejects a second watering")
	_check(_tiller._soil_state[TEST_CELL], "watered plot turns wet")

	# 睡一觉：浇过水的作物长一阶，浇水标记清空、土变干
	var time := _main.get_node("Systems/Time")
	var day_before: int = time.day
	time.sleep()
	_check(time.day == day_before + 1, "sleeping advances the calendar day")
	_check(time.minutes == 6 * 60, "sleeping resets the clock to 06:00")
	_check(crop.stage == 1, "watering advances one stage overnight")
	_check(not crop.watered, "watering flag cleared for the new day")
	_check(not _tiller._soil_state[TEST_CELL], "soil dries overnight")

	# 没浇水的作物睡一觉不长
	crop.stage = 1
	time.sleep()
	_check(crop.stage == 1, "unwatered crop does not grow")

	# 连续浇到成熟（每睡一觉前浇一次）
	for day in 3:
		_tiller._on_use_requested(&"watering_can", TEST_CELL)
		time.sleep()
	_check(crop.is_mature(), "crop matures after enough watered nights")
	_check(not _tiller.can_use(&"watering_can", TEST_CELL), "mature crop no longer needs water")

	# 站在作物下方朝上，顶部提示应给出收获键
	var player := _main.get_node("Farm/World/Player") as CharacterBody2D
	player.global_position = Vector2(TEST_CELL * 16) + Vector2(8, 25)
	player.set("_facing", &"up")
	await physics_frame
	_check(_tiller.target_cell() == TEST_CELL, "player faces the crop cell")
	_check(_tiller.interaction_hint(&"hoe").contains("F 收获"), "hint offers harvest key")

	# 收获：走真实 F 键（交互键）。F 不参与工具切换，按下只收获不换工具。
	var harvest_before: int = _inventory.count_of(&"carrot")
	var tool_before: StringName = player.current_tool
	player._unhandled_input(_key_event(KEY_F))
	_check(player.current_tool == tool_before, "F harvests instead of switching tool")
	_check(_inventory.count_of(&"carrot") == harvest_before + 1, "harvest lands in bag")
	_check(not _tiller._crops.has(TEST_CELL), "harvested cell cleared")
	_check(_tiller.can_use(&"seeds", TEST_CELL), "cleared cell can be replanted")

	# 交互键已经独立成 F，E 只负责切工具
	var tool_after: StringName = player.current_tool
	_check(_key_event(KEY_E).is_action_pressed(&"tool_next"), "E is still bound to tool_next")
	_check(not _key_event(KEY_E).is_action_pressed(&"interact"), "E no longer triggers interaction")
	player._unhandled_input(_key_event(KEY_E))
	_check(player.current_tool != tool_after, "E cycles tools with nothing to harvest")

	# 背包满时收获失败，但作物保留在格子上
	_tiller._on_use_requested(&"seeds", TEST_CELL)
	var kept: Crop = _tiller._crops[TEST_CELL]
	kept.stage = kept.data.last_stage()
	_check(kept.is_mature(), "second crop forced mature")
	# 先清空再灌满 24 格，确保背包真的没有余量（否则胡萝卜会堆叠进旧格）
	for index in _inventory.slot_count():
		var slot: Dictionary = _inventory.item_at(index)
		if not slot.is_empty():
			_inventory.remove_item(slot[&"id"], int(slot[&"count"]))
	_check(_inventory.add_item(&"wood", 99 * (_inventory.slot_count() - Inventory.TOOL_IDS.size())) == 0, "all cargo slots filled, permanent tools retained")
	var carrot_before: int = _inventory.count_of(&"carrot")
	var stamina_before: int = int(_main.get_node("Systems/Stamina").value)
	_tiller.interact(TEST_CELL)
	_check(_tiller._crops.has(TEST_CELL), "full bag keeps the crop on the field")
	_check(_inventory.count_of(&"carrot") == carrot_before, "full bag stores no harvest")
	_check(int(_main.get_node("Systems/Stamina").value) == stamina_before, "full bag harvest never spends stamina")

	# —— 季节限制：番茄只在夏天能种 ——
	var tomato: CropData = load("res://data/crops/tomato.tres")
	_check(not tomato.grows_in(&"spring") and tomato.grows_in(&"summer"), "tomato is summer only")
	_check(tomato.seasons_text() == "夏", "season text lists 夏")
	# 清空背包并把唯一可播种子换成番茄，让 _seed_id() 指向它
	for index in _inventory.slot_count():
		var slot: Dictionary = _inventory.item_at(index)
		if not slot.is_empty():
			_inventory.remove_item(slot[&"id"], int(slot[&"count"]))
	_inventory.add_item(&"tomato_seeds", 2)
	_check(_tiller._seed_id() == &"tomato_seeds", "tomato seeds become the active seed")

	var season_cell: Vector2i = TEST_CELL + Vector2i(1, 0)
	_tiller._on_use_requested(&"hoe", season_cell)
	_check(_tiller._soil_state.has(season_cell), "neighbour cell tilled for the season test")
	time.day = 1
	_check(_tiller._current_season() == &"spring", "time starts in spring")
	_check(not _tiller.can_use(&"seeds", season_cell), "tomato is rejected in spring")
	time.day = 29
	_check(_tiller._current_season() == &"summer", "day 29 is summer")
	_check(_tiller.can_use(&"seeds", season_cell), "tomato is accepted in summer")
	time.day = 1

	_check_stamina_batching()
	await _check_atomic_harvest()
	_check(_atomic_end, "all observer, persistence and rejection probes reached end")
	print("[crops] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	_main.queue_free()
	await process_frame
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_stamina_batching() -> void:
	var energy: Node = preload("res://scripts/player/stamina.gd").new()
	var values: Array[int] = []
	var rejected: Array[int] = [0]
	energy.changed.connect(func(value: int) -> void: values.append(value))
	energy.rejected.connect(func() -> void: rejected[0] += 1)
	energy.begin_update()
	energy.begin_update()
	_check(energy.spend(10) and energy.value == 90 and energy.to_dict().value == 90 and values.is_empty(), "batch spend commits synchronously without publishing partial value")
	energy.spend(5)
	energy.end_update()
	_check(values.is_empty() and energy.value == 85, "nested stamina batch does not publish before the outer boundary")
	energy.refill()
	energy.wake_weary()
	energy.from_dict({"value": 70})
	_check(values.is_empty(), "refill, weary wake and restore share the stamina batch contract")
	energy.end_update()
	_check(values == [70], "outer stamina batch synchronously publishes one final value")
	energy.begin_update()
	energy.end_update()
	energy.end_update()
	_check(values == [70], "empty or unmatched stamina end does not duplicate notification")
	_check(energy.spend(2) and values == [70, 68], "ordinary stamina spend still notifies before returning")
	energy.refill()
	energy.wake_weary()
	energy.from_dict({"value": 17})
	_check(values == [70, 68, 100, 50, 17], "ordinary refill, weary wake and restore remain synchronous")
	_check(not energy.spend(500) and energy.value == 17 and rejected[0] == 1 and values.size() == 5, "insufficient stamina retains its rejection signal without a value notification")
	energy.free()


func _prepare_harvest_pair(data: CropData, full: bool = false, energy_value: int = 80) -> void:
	_main.get_node("Systems/Time").from_dict({"day": 29 if data.id == &"blueberry" else 1, "minutes": 360})
	var records: Array[Dictionary] = []
	for cell: Vector2i in [TEST_CELL, OTHER_CELL]:
		records.append({"id": String(data.id), "x": cell.x, "y": cell.y, "stage": data.last_stage(), "stage_age": 0, "watered": true, "regrowing": false})
	_tiller.from_dict({"tilled": [[TEST_CELL.x, TEST_CELL.y], [OTHER_CELL.x, OTHER_CELL.y]], "watered": [[TEST_CELL.x, TEST_CELL.y], [OTHER_CELL.x, OTHER_CELL.y]], "crops": records})
	var slots: Array[Dictionary] = []
	for id: StringName in Inventory.TOOL_IDS: slots.append({"id": String(id), "count": 1})
	if full:
		while slots.size() < _inventory.slot_count(): slots.append({"id": "stone", "count": 99})
	_inventory.from_dict({"slots": slots})
	_inventory.today_collected = 0
	_main.get_node("Systems/Stamina").from_dict({"value": energy_value})


func _snapshot_crop(snapshot: Dictionary, cell: Vector2i) -> Dictionary:
	for record: Dictionary in snapshot.farm.crops:
		if int(record.x) == cell.x and int(record.y) == cell.y: return record
	return {}


func _snapshot_count(snapshot: Dictionary, id: StringName) -> int:
	var count: int = 0
	for slot: Dictionary in snapshot.inventory.slots:
		if StringName(slot.get("id", "")) == id: count += int(slot.get("count", 0))
	return count


func _assert_committed_harvest(snapshot: Dictionary, data: CropData, label: String) -> void:
	_check(_snapshot_count(snapshot, data.harvest_item) == data.harvest_count, label + ": exactly one harvest in the inventory snapshot")
	_check(int(snapshot.stamina.value) == 80 - _tiller.tool_cost(&"harvest"), label + ": snapshot includes exactly one stamina charge")
	var harvested: Dictionary = _snapshot_crop(snapshot, TEST_CELL)
	if data.regrow_days > 0:
		_check(not harvested.is_empty() and bool(harvested.regrowing) and not bool(harvested.watered) and int(harvested.stage) == data.last_stage() - 1 and int(harvested.stage_age) == 0, label + ": regrowing crop is already reset before notification")
	else:
		_check(harvested.is_empty() and not snapshot.farm.watered.has([TEST_CELL.x, TEST_CELL.y]), label + ": one-shot crop is absent and soil already dry before notification")
	var other: Dictionary = _snapshot_crop(snapshot, OTHER_CELL)
	_check(not other.is_empty() and int(other.stage) == data.last_stage() and bool(other.watered), label + ": reentry cannot harvest or modify the neighbouring crop")


func _observe_harvest(source: String, context: Dictionary) -> void:
	context.notifications[source] = int(context.notifications.get(source, 0)) + 1
	if context.in_callback:
		_check(false, "recursive " + source + " notification during one harvest")
		return
	context.in_callback = true
	var data: CropData = context.data
	var save: Node = _main.get_node("Systems/Save")
	var before: Dictionary = save.collect()
	_assert_committed_harvest(before, data, source + " before reentry")
	_tiller.interact(TEST_CELL)
	_tiller.interact(OTHER_CELL)
	_assert_committed_harvest(save.collect(), data, source + " after same/cross-cell reentry")
	var receipt: Dictionary = _tiller.harvest_info(TEST_CELL)
	_check(receipt.get("id") == String(data.harvest_item) and int(receipt.get("count", 0)) == data.harvest_count, source + ": legacy action query sees a committed harvest receipt")
	receipt["count"] = 999
	_check(int(_tiller.harvest_info(TEST_CELL).get("count", 0)) == data.harvest_count, source + ": returned receipt cannot mutate the pending action fact")
	var encoded: Variant = JSON.parse_string(JSON.stringify(save.collect()))
	_check(encoded is Dictionary, source + ": observer snapshot encodes as JSON")
	if encoded is Dictionary: context.snapshots.append({"label": source + " JSON", "data": encoded})
	_check(save.save_game(), source + ": observer can synchronously save the complete transaction to isolated disk")
	var disk: Dictionary = save.storage.read(save.save_path())
	_check(not disk.is_empty(), source + ": observer disk save is readable")
	if not disk.is_empty():
		_assert_committed_harvest(disk, data, source + " disk")
		context.snapshots.append({"label": source + " disk", "data": disk})
	context.in_callback = false


func _check_atomic_harvest() -> void:
	var save: Node = _main.get_node("Systems/Save")
	var energy: Node = _main.get_node("Systems/Stamina")
	save.use_slot(3)
	for id: String in ["carrot", "blueberry"]:
		var data: CropData = load("res://data/crops/" + id + ".tres")
		_prepare_harvest_pair(data)
		var context: Dictionary = {"data": data, "notifications": {}, "in_callback": false, "snapshots": []}
		var inventory_changed := _observe_harvest.bind("inventory.changed", context)
		var item_added := func(_id: StringName, _amount: int) -> void: _observe_harvest("inventory.item_added", context)
		var stamina_changed := func(_value: int) -> void: _observe_harvest("stamina.changed", context)
		var action_completed := func(tool: StringName, _cell: Vector2i) -> void:
			if tool == &"harvest": _observe_harvest("action_completed", context)
		_inventory.changed.connect(inventory_changed)
		_inventory.item_added.connect(item_added)
		energy.changed.connect(stamina_changed)
		_tiller.action_completed.connect(action_completed)
		_tiller.interact(TEST_CELL)
		_inventory.changed.disconnect(inventory_changed)
		_inventory.item_added.disconnect(item_added)
		energy.changed.disconnect(stamina_changed)
		_tiller.action_completed.disconnect(action_completed)
		for source: String in ["inventory.changed", "inventory.item_added", "stamina.changed", "action_completed"]:
			_check(int(context.notifications.get(source, 0)) == 1, id + ": exactly one " + source + " notification")
		_check(context.snapshots.size() == 8, id + ": all four observers captured both JSON and disk snapshots")
		_check(_inventory.today_collected == data.harvest_count, id + ": repeated observer harvests do not inflate collection statistics")
		if data.regrow_days == 0: _check(_tiller.harvest_info(TEST_CELL).is_empty(), "one-shot receipt expires after synchronous notification")
		# 锁只覆盖本笔事务，正常下一次收获仍能操作另一格。
		_tiller.interact(OTHER_CELL)
		_check(_inventory.count_of(data.harvest_item) == data.harvest_count * 2 and int(energy.value) == 80 - _tiller.tool_cost(&"harvest") * 2, id + ": next independent harvest is allowed after observers return")
		for record: Dictionary in context.snapshots:
			for attempt: int in 3:
				save.apply(record.data)
				_tiller.interact(TEST_CELL)
				_assert_committed_harvest(save.collect(), data, "%s %s restore %d" % [id, record.label, attempt])
			await process_frame
		_check(save.load_game(3), id + ": observer-written real slot reloads through SaveSystem")
		_tiller.interact(TEST_CELL)
		_assert_committed_harvest(save.collect(), data, id + " actual disk load")
		_check_harvest_rejection(data, true, 80)
		_check_harvest_rejection(data, false, 1)
		await process_frame
	_atomic_end = true


func _check_harvest_rejection(data: CropData, full: bool, energy_value: int) -> void:
	_prepare_harvest_pair(data, full, energy_value)
	var energy: Node = _main.get_node("Systems/Stamina")
	var save: Node = _main.get_node("Systems/Save")
	var baseline: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	var notices: Array[int] = [0]
	var inventory_changed := func() -> void: notices[0] += 1
	var item_added := func(_id: StringName, _amount: int) -> void: notices[0] += 1
	var stamina_changed := func(_value: int) -> void: notices[0] += 1
	var action_completed := func(_tool: StringName, _cell: Vector2i) -> void: notices[0] += 1
	_inventory.changed.connect(inventory_changed)
	_inventory.item_added.connect(item_added)
	energy.changed.connect(stamina_changed)
	_tiller.action_completed.connect(action_completed)
	_tiller.interact(TEST_CELL)
	_tiller.interact(OTHER_CELL)
	_inventory.changed.disconnect(inventory_changed)
	_inventory.item_added.disconnect(item_added)
	energy.changed.disconnect(stamina_changed)
	_tiller.action_completed.disconnect(action_completed)
	var after: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	var label: String = String(data.id) + (" full bag" if full else " low stamina")
	_check(after.inventory == baseline.inventory and after.farm == baseline.farm and after.stamina == baseline.stamina, label + ": rejected harvest preserves every core fact")
	_check(notices[0] == 0 and _inventory.today_collected == 0, label + ": rejected harvest publishes no successful result")
