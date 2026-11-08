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
		var story_probe: GDScript = load(get_script().resource_path.get_base_dir().path_join("packaged_story_events.gd"))
		await story_probe.run(self, _main, _check)
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
	await _exercise_quest(inventory, economy, save)
	await _exercise_mail(inventory, economy, save)
	await _exercise_chapter(inventory, save)
	await process_frame


func _exercise_chapter(inventory: Inventory, save: Node) -> void:
	for quest: QuestData in _main.quests.definitions():
		if _main.quests.status_of(quest.id) == 3: continue
		_check(_main.quests.accept_for(quest.giver, quest.id), "pack accepts next authored quest")
		for step: QuestStep in quest.deliver_steps(): inventory.add_item(step.item_id, step.count, &"transfer")
		_check(_main.quests.deliver_for(quest.giver, quest.id), "pack settles next authored quest")
	_check(_main.crafts.unlocked(), "pack chapter completion unlocks real crafting")
	inventory.add_item(&"carrot", 1, &"transfer")
	inventory.add_item(&"fiber", 2, &"transfer")
	var before: int = inventory.count_of(&"carrot_seeds")
	var house: Node = _main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/house_interior.tscn"))
	await process_frame
	var table: Node
	for actor: Node in get_nodes_in_group(&"interactable"):
		if actor.name == &"SeedWorkbench": table = actor
	_check(table != null, "pack retains the interior table and creates its runtime workbench interaction")
	if table != null: table.interact(Vector2i.ZERO)
	var view: Control = _main.get_node("UI/WorkbenchPanel")
	var make: Button
	for button: Button in view.find_children("*", "Button", true, false):
		if button.text == "制作 · 胡萝卜种子包": make = button
	_check(view.visible and make != null and not make.disabled, "pack exposes the real workbench craft button")
	if make != null: make.pressed.emit()
	_check(inventory.count_of(&"carrot_seeds") == before + 4, "pack loads crafting Resource and produces four real seed items")
	view.set_open(false)
	house.exit_house()
	var player: Node = _main.regions.player
	var chapter: Node = _main.get_node("Systems/ChapterFlow")
	var scene: Node = _main.get_node("Systems/ChapterCutscene")
	chapter.enabled = true
	chapter.request_followup()
	await process_frame
	await process_frame
	_check(scene.is_playing() and player.has_input_leases(), "pack starts the actual chapter event with an owned input lease")
	_check(scene.skip() and not player.has_input_leases(), "pack skips the chapter and releases input")
	_check(_main.events.has_completed(&"ch1_market_memory") and not _main.mail.status(&"chapter_one_complete").is_empty(), "pack commits chapter story and letter once")
	_check(save.save_game() and save.load_game(3), "pack persists the full chapter result")
	_check(inventory.count_of(&"carrot_seeds") == before + 4 and _main.crafts.unlocked(), "pack reload retains crafted products and entitlement")


func _exercise_mail(inventory: Inventory, economy: Economy, save: Node) -> void:
	var mail: RefCounted = _main.mail
	_check(mail.definition(&"farm_welcome") != null, "pack discovers authored mail resources")
	var letter := MailData.new()
	letter.id = &"pack_mail"
	letter.sender = "园艺师"
	letter.title = "农场来信"
	letter.coins = 5
	var item := MailAttachment.new()
	item.item_id = &"wood"
	item.count = 1
	letter.attachments.append(item)
	mail.register_definition(letter)
	_check(mail.deliver(letter.id) and not mail.deliver(letter.id), "pack delivers a stable mail ID once")
	var coins: int = economy.coins
	var wood: int = inventory.count_of(&"wood")
	_main.get_node("Farm/World/Mailbox").interact(Vector2i.ZERO)
	var view: Control = _main.get_node("UI/MailboxPanel")
	view.selected.emit(letter.id)
	view.claim_button.pressed.emit()
	_check(view.visible and mail.status(letter.id).claimed and economy.coins == coins + 5 and inventory.count_of(&"wood") == wood + 1, "pack claims attachments through the real mailbox view")
	view.set_open(false)
	_check(save.save_game() and save.load_game(3) and not mail.claim(letter.id), "pack restores mail without awarding attachments twice")
	_check(economy.coins == coins + 5 and inventory.count_of(&"wood") == wood + 1, "pack persists the complete mail reward transaction")
	await process_frame


func _exercise_quest(inventory: Inventory, economy: Economy, save: Node) -> void:
	var quests: RefCounted = _main.quests
	_check(quests.definitions().size() == 6, "pack loads authored chapter definitions")
	var house: Node = _main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/shop_interior.tscn"))
	await process_frame
	var boss: Node
	for actor: Node in get_nodes_in_group(&"interactable"):
		if actor.has_method(&"configure_quest_dialogue") and actor.get(&"npc_id") == &"shopkeeper":
			boss = actor
	_check(boss != null, "pack creates an actual indoor quest giver")
	if boss == null:
		return
	_check(boss.quest_options.is_valid() and boss.quest_response.is_valid(), "pack injects lazy NPC quest ports")
	var dialogue: Control = _main.get_node("UI/DialoguePanel")
	var before: int = economy.coins
	inventory.add_item(&"fiber", 6, &"transfer")
	boss.interact(Vector2i.ZERO)
	await _press_quest_button(dialogue, "委托：修好摊位的门板")
	await _advance_quest_lines(dialogue)
	await _press_quest_button(dialogue, "接下这份委托")
	_check(quests.status_of(&"ch1_01_gate") == 2, "pack accepts through a real dialogue button")
	await _press_quest_button(dialogue, "交付物品并领取奖励")
	_check(quests.status_of(&"ch1_01_gate") == 3 and economy.coins == before + 120, "pack dialogue commits the quest reward")
	dialogue.close()
	_check(save.save_game() and save.load_game(3), "pack writes and restores chapter state")
	_check(quests.status_of(&"ch1_01_gate") == 3 and economy.coins == before + 120, "pack restore never replays the quest reward")
	house.exit_house()


func _quest_button(dialogue: Control, text: String) -> Button:
	for child: Node in dialogue.get_node("%Options").get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text == text:
			return child
	return null


func _press_quest_button(dialogue: Control, text: String) -> void:
	var button: Button = _quest_button(dialogue, text)
	_check(button != null, "pack dialogue exposes " + text)
	if button != null:
		button.pressed.emit()
	await process_frame


func _advance_quest_lines(dialogue: Control) -> void:
	for step: int in 12:
		var button: Button = _quest_button(dialogue, "继续")
		if button == null:
			return
		button.pressed.emit()
		await process_frame
	_check(false, "pack quest dialogue must terminate")
