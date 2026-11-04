extends SceneTree
## 时间与存档回归：日期推进、睡觉结算、存读档一致性、坏档容错。
## --headless --path . --script res://tools/check/check_calendar.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_CELL := Vector2i(16, 6)

var _main: Node2D
var _time: Node
var _save: Node
var _economy: Economy
var _inventory: Inventory
var _tiller: Node
var _player: CharacterBody2D
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[calendar] FAIL: " + message)


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	_time = _main.get_node("Systems/Time")
	_save = _main.get_node("Systems/Save")
	# 必须在 deferred 的自动读档之前关掉，否则真实存档会污染断言
	_save.autoload_enabled = false
	# 锁晴天：雨天会自动帮作物浇水，"没浇水不长"的断言会随机失败。
	var weather := get_first_node_in_group(&"weather") as Node
	if weather != null and weather.has_method(&"lock"):
		weather.call("lock", &"sunny")
	_save.delete_save()
	_economy = _main.get_node("Systems/Economy") as Economy
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	_tiller = _main.get_node("Farm/Tiller")
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	await process_frame
	await process_frame

	_check(_time != null, "time system exists")
	_check(_time.day == 1, "starts on day 1")
	_check(_time.minutes == 6 * 60, "starts at 06:00")
	_check(_time.clock_text() == "06:00", "clock text at 06:00")
	_check(_main.get_node_or_null("Farm/World/CottageDoor") != null, "cottage door in world")
	_check(_main.get_node_or_null("UI/DaySummary") != null, "day summary panel exists")

	# 昼夜色调：白天是纯白，入夜变暗
	var tint := _main.get_node("DayNightTint") as CanvasModulate
	_time.time_changed.emit(_time.day, 12 * 60)
	_check(tint.color.is_equal_approx(Color.WHITE), "daytime keeps the world bright")
	_time.time_changed.emit(_time.day, 22 * 60)
	_check(tint.color.v < 0.95, "night darkens the world")

	# 睡觉：日期 +1，时间回到 06:00
	var day_before: int = _time.day
	_time.sleep()
	_check(_time.day == day_before + 1, "sleeping advances the day")
	_check(_time.minutes == 6 * 60, "sleeping resets to 06:00")

	# 准备一个存档局面：一株浇过水长了一阶的作物 + 金币 + 背包
	_tiller._on_use_requested(&"hoe", TEST_CELL)
	_inventory.add_item(&"carrot_seeds", 2)
	_tiller._on_use_requested(&"seeds", TEST_CELL)
	var crop: Crop = _tiller._crops.get(TEST_CELL)
	_check(crop != null, "crop planted for the save test")
	_tiller._on_use_requested(&"watering_can", TEST_CELL)
	_time.sleep()
	_check(crop.stage == 1, "watered crop grows one stage overnight")
	_economy.coins = 777
	_inventory.add_item(&"tomato", 3)
	_player.global_position = Vector2(300, 200)
	var saved_day: int = _time.day
	var saved_stage: int = crop.stage

	_check(_save.save_game(), "save writes a file")
	_check(_save.has_save(), "save file exists after writing")

	# 打乱运行时，再读档
	_economy.coins = 1
	for index in _inventory.slot_count():
		var slot: Dictionary = _inventory.item_at(index)
		if not slot.is_empty():
			_inventory.remove_item(slot[&"id"], int(slot[&"count"]))
	_tiller.from_dict({})
	_player.global_position = Vector2(50, 50)
	_time.day = 1

	_check(_save.load_game(), "load succeeds")
	_check(_economy.coins == 777, "coins restored")
	_check(_inventory.count_of(&"tomato") == 3, "inventory restored")
	_check(_time.day == saved_day, "calendar day restored")
	var restored: Crop = _tiller._crops.get(TEST_CELL)
	_check(restored != null, "crop restored on its cell")
	if restored != null:
		_check(restored.stage == saved_stage, "crop stage restored")
	_check(_tiller._soil_state.has(TEST_CELL), "tilled cell restored")
	_check(_player.global_position.is_equal_approx(Vector2(300, 200)), "player position restored")

	# 坏档：不能崩，文件被隔离
	var file := FileAccess.open(_save.save_path(), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	_check(not _save.load_game(), "broken save is rejected")
	_check(not _save.has_save(), "broken save is quarantined")

	# 缺字段的旧档：字段缺失走默认值
	file = FileAccess.open(_save.save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "coins": 42}))
	file.close()
	_check(_save.load_game(), "save with missing fields still loads")
	_check(_economy.coins == 42, "partial save applies available fields")

	_save.delete_save()

	# —— 季节：28 天一季度，由天数推导（不需要额外存档字段） ——
	_time.day = 1
	_check(_time.season() == &"spring", "day 1 is spring")
	_check(_time.day_of_season() == 1, "day 1 is the first day of the season")
	_time.day = 28
	_check(_time.season() == &"spring" and _time.day_of_season() == 28, "day 28 is the last spring day")
	var seasons_seen: Array = []
	var on_season := func(season: StringName, _year: int) -> void: seasons_seen.append(season)
	_time.season_changed.connect(on_season)
	_time.day = 29
	_check(_time.season() == &"summer", "day 29 turns summer")
	_time.time_changed.emit(_time.day, _time.minutes)
	await process_frame
	var hud := _main.get_node_or_null("UI/HUD")
	var clock_label := hud.find_child("TimeLabel", true, false) as Label if hud != null else null
	_check(clock_label != null and clock_label.text.contains("夏"), "hud shows the current season")
	_check(_time.day_of_season() == 1, "summer starts at day 1")
	_time.sleep()
	_check(seasons_seen == [], "sleeping within a season does not fire season_changed")
	_time.day = 56
	_time.sleep()
	_check(seasons_seen == [&"autumn"], "crossing 56 days fires season_changed once")
	_time.season_changed.disconnect(on_season)
	_time.day = 113
	_check(_time.season() == &"spring" and _time.year() == 2, "day 113 starts year 2 in spring")

	print("[calendar] %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_main.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)
