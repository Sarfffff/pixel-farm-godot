extends SceneTree
## 从实际 PCK 加载游戏；本文件由包外绝对路径启动，不能依赖被排除的开发资源。

var _failures: int = 0
var _checks: int = 0
var _main: Node
const CELLS: Array[Vector2i] = [Vector2i(18, 7), Vector2i(19, 7), Vector2i(20, 7)]


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[packaged_runtime] FAIL: " + message)


func _run() -> void:
	var directory: String = ProjectSettings.get_setting("application/config/custom_user_dir_name", "")
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false) or not directory.begins_with("PixelFarmChecks_"):
		printerr("[packaged_runtime] FAIL: isolated user directory required")
		quit(2)
		return
	_check(not ResourceLoader.exists("res://tools/check/check_architecture.gd"), "development checks excluded from package")
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.queue_free()
	await process_frame
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Systems/Save").autoload_enabled = false
	for actor: String in ["Player", "Gardener", "Carpenter", "Fisherman", "ChickenCoop", "Chicken1", "Chicken2", "CottageDoor", "ShopDoor"]:
		_check(_main.has_node("Farm/World/" + actor), "export retains " + actor)
	if _failures == 0:
		root.add_child(_main)
		current_scene = _main
		await process_frame
		await process_frame
		await physics_frame
		await _exercise_loop()
	if _main.is_inside_tree():
		_main.queue_free()
		await process_frame
	else:
		_main.free()
	await preload("res://scripts/platform/app_lifecycle.gd").prepare_exit(self)
	print("[packaged_runtime] %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	var code: int = 0 if _failures == 0 else 1
	print("[checks] lifecycle complete; exit=%d" % code)
	quit(code)


func _exercise_loop() -> void:
	var inventory: Inventory = _main.get_node("Systems/Inventory")
	var tiller: Node = _main.get_node("Farm/Tiller")
	var time: Node = _main.get_node("Systems/Time")
	var economy: Economy = _main.get_node("Systems/Economy")
	var save: Node = _main.get_node("Systems/Save")
	var trade: Node = get_first_node_in_group(&"trade")
	time.running = false
	_check(OS.has_feature("farm_release"), "actual pack carries production feature")
	_check("--enable-dev-tools" in OS.get_cmdline_user_args(), "pack probe intentionally requests development tools")
	var controls: Node = _main.get_node("Systems/DevelopmentControls")
	var before_day: int = time.day
	_check(not controls.enabled and not controls.request_advance(), "pack denies explicit development activation")
	var skip_day := InputEventAction.new()
	skip_day.action = &"next_day"
	skip_day.pressed = true
	Input.parse_input_event(skip_day)
	await process_frame
	_check(time.day == before_day, "pack input cannot advance the day")
	_main.get_node("Systems/Weather").lock(&"sunny")
	_check(inventory.definitions().size() >= 41, "logical item resources load from PCK")
	_check(tiller.crop_definitions().size() >= 6, "logical crop resources load from PCK")
	if _failures > 0:
		return
	_check(economy.coins == 500 and inventory.count_of(&"carrot_seeds") == 5, "starting resources")
	for cell: Vector2i in CELLS:
		tiller._on_use_requested(&"seeds", cell)
	_check(inventory.count_of(&"carrot_seeds") == 2, "planting consumes seeds")
	for night: int in 3:
		for cell: Vector2i in CELLS:
			tiller._on_use_requested(&"watering_can", cell)
		time.sleep()
	for cell: Vector2i in CELLS:
		tiller.interact(cell)
	_check(inventory.count_of(&"carrot") == 3, "watering and three nights produce harvest")
	_check(trade.sell(&"carrot", 3) == 3 and economy.coins == 575, "harvest sale pays actual wallet")
	_check(trade.purchase(&"carrot_seeds", 3) == 3 and economy.coins == 551, "profit buys next production round")
	var expected_seeds: int = inventory.count_of(&"carrot_seeds")
	save.use_slot(3)
	_check(save.save_game(), "packaged game writes isolated save")
	inventory.remove_item(&"carrot_seeds", expected_seeds)
	economy.spend(10)
	_check(save.load_game(3), "packaged game reloads save")
	_check(inventory.count_of(&"carrot_seeds") == expected_seeds and economy.coins == 551, "save restores inventory and wallet")
	time.from_dict({"day": 28, "minutes": 360})
	tiller.commit_tool_action(&"seeds", CELLS[0])
	time.sleep()
	var seasonal: Dictionary = tiller.to_dict()
	_check(time.day == 29 and seasonal.crops.size() == 1 and bool(seasonal.crops[0].withered), "pack applies seasonal withering at the new dawn")
	_check(save.save_game() and save.load_game(3) and bool(tiller.to_dict().crops[0].withered), "pack preserves dead crops through disk save")
	_check(_main.get_node("UI/ShopPanel").seed_information.call(&"carrot_seeds").contains("当前季节不可播种"), "pack exposes real seasonal shop information")
	tiller.interact(CELLS[0])
	_check(tiller.to_dict().crops.is_empty(), "pack clears dead crop through normal interaction port")
	await process_frame
