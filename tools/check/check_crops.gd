extends SceneTree
## 作物回归：播种消耗种子、浇水推进阶段、成熟提示、收获进背包、满包不丢作物。
## --headless --path . --script res://tools/check/check_crops.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_CELL := Vector2i(18, 6)

var _main: Node2D
var _tiller: Node2D
var _inventory: Inventory
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
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
	_main = load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	# 关掉自动读档：测试固定从干净的开局状态出发，不受真实存档影响
	_main.get_node("Systems/Save").autoload_enabled = false
	# 锁晴天：雨天会自动替玩家浇所有作物，断言"没浇水就不长"会变成随机失败。
	var weather := get_first_node_in_group(&"weather") as Node
	if weather != null:
		weather.call(&"lock", &"sunny")
	await physics_frame
	await physics_frame
	await create_timer(0.2).timeout
	_tiller = _main.get_node("Farm/Tiller") as Node2D
	_inventory = _main.get_node("Systems/Inventory") as Inventory

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
	_check(_tiller.interaction_hint(&"hoe").contains("E 收获"), "hint offers harvest key")

	# 收获：走真实 E 键。E 同时绑定 tool_next，交互必须优先于切工具。
	var harvest_before: int = _inventory.count_of(&"carrot")
	var tool_before: StringName = player.current_tool
	player._unhandled_input(_key_event(KEY_E))
	_check(player.current_tool == tool_before, "E harvests instead of switching tool")
	_check(_inventory.count_of(&"carrot") == harvest_before + 1, "harvest lands in bag")
	_check(not _tiller._crops.has(TEST_CELL), "harvested cell cleared")
	_check(_tiller.can_use(&"seeds", TEST_CELL), "cleared cell can be replanted")

	# 身边一圈没有可收获对象时，E 应回落成切换工具
	var tool_after: StringName = player.current_tool
	_check(_key_event(KEY_E).is_action_pressed(&"tool_next"), "E is also bound to tool_next")
	player._unhandled_input(_key_event(KEY_E))
	_check(player.current_tool != tool_after, "E still cycles tools with nothing to harvest")

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
	_tiller.interact(TEST_CELL)
	_check(_tiller._crops.has(TEST_CELL), "full bag keeps the crop on the field")
	_check(_inventory.count_of(&"carrot") == carrot_before, "full bag stores no harvest")

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

	print("[crops] %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_main.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)
