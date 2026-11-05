extends SceneTree
## 真实主场景回归；不读写玩家存档。-- --preview 同时渲染验收图。

var main: Node2D
var activities: Node
var inventory: Inventory
var clock: Node
var stamina: Node
var failures: int = 0
var checks: int = 0


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[activities] FAIL: " + message)


func settle() -> void:
	for frame: int in 4:
		await process_frame


func empty_bag() -> void:
	inventory.from_dict({"slots": []})


func full_bag(extra: Array = []) -> void:
	var slots: Array = []
	for id: StringName in Inventory.TOOL_IDS:
		slots.append({"id": String(id), "count": 1})
	slots.append_array(extra)
	while slots.size() < inventory.slot_count():
		slots.append({"id": "wood", "count": 99})
	inventory.from_dict({"slots": slots})


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	main = load("res://scenes/main.tscn").instantiate()
	var save: Node = main.get_node("Systems/Save")
	save.autoload_enabled = false
	root.add_child(main)
	current_scene = main
	save.remove_from_group(&"save")
	clock = main.get_node("Systems/Time")
	clock.running = false
	main.get_node("Systems/Weather").lock(&"sunny")
	inventory = main.get_node("Systems/Inventory")
	activities = main.get_node("Systems/FarmActivities")
	activities.set_process(false)
	stamina = main.get_node("Systems/Stamina")
	await settle()
	var initial: Dictionary = save.collect()
	check(get_nodes_in_group(&"inventory").size() == 1, "chest does not register another inventory")
	for id: StringName in [&"potato", &"potato_seeds", &"blueberry", &"blueberry_seeds", &"bamboo_rod", &"crucian_carp", &"common_carp", &"pickled_tomato", &"wild_flower", &"wild_mushroom", &"wild_blackberry"]:
		check(inventory.definition(id) != null and inventory.definition(id).icon != null, "definition and original icon: " + String(id))
	_test_storage()
	_test_forage()
	_test_processing()
	_test_crops()
	_test_community()
	_test_fishing()
	await _test_modals()
	var state: Dictionary = activities.to_dict()
	var snapshot: Dictionary = save.collect()
	activities.from_dict({})
	save.apply(JSON.parse_string(JSON.stringify(snapshot)))
	check(activities.to_dict() == state, "all activities roundtrip through actual save system")
	initial.erase(&"farm_activities")
	save.apply(initial)
	check(activities.storage.count_of(&"tomato") == 0 and activities.depleted.is_empty(), "old save without activities starts safely")
	if OS.get_cmdline_user_args().has("--preview"):
		await _preview()
	main.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	for audio: Node in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stream = null
	await create_timer(0.1).timeout
	await settle()
	print("[activities] %d checks, %d failures" % [checks, failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if failures == 0 else 1)


func _test_storage() -> void:
	empty_bag()
	inventory.add_item(&"tomato", 8)
	check(activities.deposit(&"tomato", 5) == 5 and inventory.count_of(&"tomato") == 3, "deposit conserves cargo")
	var collected: int = inventory.today_collected
	check(activities.withdraw(&"tomato", 2) == 2 and activities.storage.count_of(&"tomato") == 3, "withdraw conserves cargo")
	check(inventory.today_collected == collected, "transfers do not inflate daily harvest")
	check(activities.deposit(&"hoe", 1) == 0 and inventory.count_of(&"hoe") == 1, "permanent tool cannot be lost in chest")
	var slots: Array = []
	for index: int in activities.settings.storage_capacity:
		slots.append({"id": "stone", "count": 99})
	activities.storage.restore(slots, inventory)
	check(activities.deposit(&"tomato", 1) == 0 and inventory.count_of(&"tomato") == 5, "full chest leaves bag intact")
	activities.storage.restore([{"id": "tomato", "count": 7}], inventory)
	full_bag()
	check(activities.withdraw(&"tomato", 7) == 0 and activities.storage.count_of(&"tomato") == 7, "full bag leaves chest intact")
	full_bag([{"id": "tomato", "count": 98}])
	check(activities.withdraw(&"tomato", 7) == 1 and activities.storage.count_of(&"tomato") == 6 and inventory.count_of(&"tomato") == 99, "partial transfer fits exactly without overflow")
	activities.storage.restore([], inventory)


func _test_forage() -> void:
	empty_bag()
	stamina.refill()
	var player: Node2D = main.get_node("Farm/World/Player")
	for index: int in 3:
		player.global_position = activities.settings.forage_positions[index] + Vector2(0, 6)
		check(player.nearby_interactable() == activities.pickups[index], "forage is discoverable through normal proximity")
		check(player._try_interact(), "gather distinct forage through player interaction " + str(index))
	check(stamina.value == 97, "gather costs one stamina each")
	check(not activities.collect_forage(0), "depleted pickup cannot duplicate")
	full_bag()
	check(not activities.collect_forage(3) and not activities.depleted.has(3) and stamina.value == 97, "full bag neither consumes pickup nor stamina")
	activities.from_dict(activities.to_dict())
	activities.on_day_started(clock.day)
	check(activities.depleted.size() == 3, "same-day reload cannot refresh forage")
	clock.sleep()
	check(activities.depleted.size() == 1, "exactly two pickups regrow overnight")
	activities.on_day_started(clock.day)
	check(activities.depleted.size() == 1, "duplicate day signal cannot refresh twice")
	var water: TileMapLayer = main.get_node("Farm/WaterCollision")
	for point: Vector2 in activities.settings.forage_positions:
		check(water.get_cell_source_id(water.local_to_map(point)) == -1, "forage is reachable on land: " + str(point))
	check(water.get_cell_source_id(water.local_to_map(activities.settings.fishing_position)) == -1, "fishing stance on land")
	check(water.get_cell_source_id(water.local_to_map(activities.settings.fishing_target)) >= 0, "bobber lands in actual water")


func _test_processing() -> void:
	empty_bag()
	check(not activities.use_processing(), "recipe requires actual ingredients")
	inventory.add_item(&"tomato", 3)
	var player: Node2D = main.get_node("Farm/World/Player")
	player.global_position = activities.settings.machine_position + Vector2(0, 12)
	check(player.nearby_interactable().kind == &"processing", "processing station is reachable through normal proximity")
	check(player._try_interact() and inventory.count_of(&"tomato") == 0 and activities.processing_ready_day > 0, "three tomatoes consumed exactly once through player interaction")
	check(not activities.use_processing(), "cannot collect before overnight completion")
	check(activities.tomorrow_text().contains("腌菜"), "sleep summary forecasts processing")
	clock.sleep()
	full_bag()
	check(not activities.use_processing() and activities.processing_ready_day > 0, "full bag retains finished product")
	empty_bag()
	check(activities.use_processing() and inventory.count_of(&"pickled_tomato") == 1, "overnight output enters bag")
	check(not activities.use_processing() and inventory.count_of(&"pickled_tomato") == 1, "cannot collect a second output")


func _test_crops() -> void:
	empty_bag()
	stamina.refill()
	var tiller: Node = main.get_node("Farm/Tiller")
	var potato: CropData = load("res://data/crops/potato.tres")
	var blueberry: CropData = load("res://data/crops/blueberry.tres")
	var first: Crop = tiller._spawn_crop(Vector2i(18, 6), potato, 0, false)
	for day: int in 2:
		first.water()
		clock.sleep()
		check(first.is_mature() == (day == 1), "potato matures in two watered nights")
	tiller.interact(Vector2i(18, 6))
	check(inventory.count_of(&"potato") == 1 and not tiller._crops.has(Vector2i(18, 6)), "potato is single harvest")
	var crop: Crop = tiller._spawn_crop(Vector2i(19, 6), blueberry, 0, false)
	check(crop.scale == Vector2.ONE and crop.texture.get_size() == Vector2(32, 32), "new crop art shares native pixel density with existing crops")
	check(crop.watered_nights_remaining() == 5, "blueberry displays actual first-harvest duration")
	clock.sleep()
	check(crop.stage == 0 and crop.stage_age == 0, "unwatered crop does not age")
	for day: int in 5:
		crop.water()
		clock.sleep()
		check(crop.is_mature() == (day == 4), "blueberry needs five watered nights")
	full_bag([{"id": "blueberry", "count": 98}])
	var before: int = stamina.value
	tiller.interact(Vector2i(19, 6))
	check(crop.is_mature() and inventory.count_of(&"blueberry") == 98 and stamina.value == before, "two-yield harvest is atomic when only one fits")
	empty_bag()
	tiller.interact(Vector2i(19, 6))
	check(inventory.count_of(&"blueberry") == 2 and crop.regrowing and tiller._crops.has(Vector2i(19, 6)), "blueberry yields two and retains plant")
	crop.water()
	clock.sleep()
	check(not crop.is_mature() and crop.stage_age == 1, "first regrowth night retained")
	check(crop.watered_nights_remaining() == 1, "regrowth hint accounts for elapsed watered nights")
	var data: Dictionary = tiller.to_dict()
	tiller.from_dict(data)
	crop = tiller._crops[Vector2i(19, 6)]
	check(crop.regrowing and crop.stage_age == 1, "regrowth progress survives farm save")
	crop.water()
	clock.sleep()
	check(crop.is_mature(), "regrowth completes in two nights")
	var legacy: Dictionary = tiller.to_dict()
	for record: Dictionary in legacy.get("crops", []):
		record.erase(&"stage_age")
		record.erase(&"regrowing")
	tiller.from_dict(legacy)
	check(tiller._crops[Vector2i(19, 6)].stage_age == 0, "legacy crop records default missing growth fields")


func _test_community() -> void:
	var community: Node = main.get_node("Systems/CommunityCenter")
	community.from_dict({"stage": 0})
	empty_bag()
	inventory.add_item(&"wood", 15)
	inventory.add_item(&"fiber", 10)
	check(community.donate() and activities.visuals.fences[1].visible, "real donation immediately repairs visible fence")
	var economy: Node = main.get_node("Systems/Economy")
	var coins: int = economy.coins
	community.from_dict(community.to_dict())
	check(economy.coins == coins, "restoring community visuals never repeats reward")
	for stage: int in 4:
		community.from_dict({"stage": stage})
		check(activities.visuals.applied_stage == stage, "community visual follows restored stage")
		check(activities.visuals.fences[1].visible == (stage >= 1), "fence repair visible")
		check(activities.visuals.stalls[0].visible == (stage >= 2), "market stalls visible")
		check(activities.visuals.sign.visible == (stage >= 3), "farm sign visible")


func _test_fishing() -> void:
	empty_bag()
	stamina.refill()
	check(not activities.start_fishing(), "fishing requires owned rod")
	var shop: Node = main.get_node("UI/ShopPanel")
	var economy: Node = main.get_node("Systems/Economy")
	var coins: int = economy.coins
	check(shop._buy(&"bamboo_rod", 80, 5) == 1 and economy.coins == coins - 80, "shop buys only one rod and deducts actual price")
	check(shop._buy(&"bamboo_rod", 80, 5) == 0, "permanent rod cannot be purchased repeatedly")
	check(activities.start_fishing() and stamina.value == 96 and activities.casts_today == 1, "casting consumes stamina and quota once")
	check(not activities.fishing_action(), "early reel cannot catch fish")
	activities.tick_fishing(4.0)
	check(activities.fishing_state == &"bite", "wait transitions to visible bite")
	check(activities.fishing_action(), "timely reel places fish in bag")
	check(inventory.count_of(&"crucian_carp") + inventory.count_of(&"common_carp") == 1, "one cast yields one of two fish")
	check(not activities.claim_fish(), "fish cannot be claimed twice")
	check(activities.start_fishing(), "second cast allowed")
	activities.tick_fishing(4.0)
	activities.tick_fishing(3.0)
	check(activities.fishing_state == &"idle" and inventory.count_of(&"crucian_carp") + inventory.count_of(&"common_carp") == 1, "missed bite yields no fish")
	check(activities.start_fishing(), "third cast allowed")
	activities.tick_fishing(4.0)
	full_bag([{"id": "bamboo_rod", "count": 1}])
	check(not activities.fishing_action() and activities.pending_fish != &"", "landed fish retained if bag becomes full")
	activities.from_dict(activities.to_dict())
	check(activities.pending_fish != &"" and activities.casts_today == 3, "pending catch and quota persist")
	empty_bag()
	inventory.add_item(&"bamboo_rod", 1)
	check(activities.claim_fish(), "pending fish can be collected after clearing bag")
	check(not activities.start_fishing(), "daily quota prevents fourth cast")
	clock.sleep()
	check(activities.casts_today == 0 and activities.start_fishing(), "next day restores fishing quota")
	activities.cancel_fishing()
	var fish: StringName = &"crucian_carp" if inventory.count_of(&"crucian_carp") > 0 else &"common_carp"
	coins = economy.coins
	var price: int = inventory.definition(fish).sell_price
	check(shop._sell(fish, price, 1) == 1 and economy.coins == coins + price, "caught fish sell through existing shop economy")


func _test_modals() -> void:
	var player: Node = main.get_node("Farm/World/Player")
	var panel: Control = activities.panel
	player.global_position = activities.settings.chest_position + Vector2(0, 12)
	check(player.nearby_interactable().kind == &"storage", "chest is nearest reachable interaction")
	var interact: InputEventKey = InputEventKey.new()
	interact.keycode = KEY_F
	interact.physical_keycode = KEY_F
	interact.pressed = true
	root.push_input(interact)
	await settle()
	check(panel.visible and player.input_locked and not main.get_node("UI/PauseMenu").can_pause(), "real F opens chest, locks movement, blocks nested pause")
	check(not main.get_node("UI/HelpPanel")._can_open(), "help cannot pause over activity modal")
	clock.running = true
	var minutes: int = clock.minutes
	clock._process(10.0)
	check(clock.minutes == minutes, "storage modal freezes game clock")
	clock.running = false
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)
	await settle()
	check(not panel.visible and not player.input_locked, "Escape closes storage and restores movement")
	panel.open(&"fishing")
	await settle()
	check(panel.fish_box.visible and not panel.lists.visible, "fishing switches panel without stale storage content")
	var casts: int = activities.casts_today
	root.push_input(interact)
	await settle()
	check(activities.fishing_state == &"waiting" and activities.casts_today == casts + 1, "real E starts one cast inside fishing panel")
	activities.tick_fishing(4.0)
	root.push_input(interact)
	await settle()
	check(activities.fishing_state == &"idle", "real E reels bite inside fishing panel")
	panel.close()
	panel.open(&"storage")
	var bag_key: InputEventKey = InputEventKey.new()
	bag_key.keycode = KEY_B
	bag_key.physical_keycode = KEY_B
	bag_key.pressed = true
	root.push_input(bag_key)
	await settle()
	check(not panel.visible and not player.input_locked and not main.get_node("UI/InventoryPanel").visible, "B closes activity without opening another panel")
	root.push_input(bag_key)
	await settle()
	check(player.input_locked and main.get_node("UI/InventoryPanel").visible, "next B opens regular backpack")
	root.push_input(bag_key)
	await settle()
	check(not player.input_locked, "closing backpack releases lock")
	panel.open(&"storage")
	main.get_node("UI/InventoryPanel").set_open(true)
	await settle()
	check(not panel.visible and player.input_locked, "opening another panel safely transfers modal lock")
	main.get_node("UI/InventoryPanel").set_open(false)
	for mode: StringName in [&"storage", &"fishing"]:
		panel.open(mode)
		for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(960, 720)]:
			root.size = resolution
			await settle()
			check(panel.get_viewport_rect().encloses(panel.get_node("Frame").get_global_rect()), "activity panel fits " + String(mode) + " at " + str(resolution))
		panel.close()
	root.size = Vector2i(1600, 900)


func _shot(name: String) -> void:
	await settle()
	await RenderingServer.frame_post_draw
	# 输出目录不入库，clone 后可能不存在，先建出来
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	root.get_texture().get_image().save_png("res://docs/screenshots/activities-" + name + ".png")


func _preview() -> void:
	empty_bag()
	inventory.add_item(&"tomato", 12)
	inventory.add_item(&"potato_seeds", 8)
	inventory.add_item(&"bamboo_rod", 1)
	main.get_node("UI/Toast").clear()
	activities.storage.add(&"wild_mushroom", 5, 99)
	var player: Node2D = main.get_node("Farm/World/Player")
	player.global_position = Vector2(552, 183)
	var camera: Node = main.get_node("Camera")
	camera.set_view_zoom(1.8, true, false)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	await _shot("world")
	activities.panel.open(&"storage")
	await _shot("storage")
	activities.panel.close()
	player.global_position = activities.settings.fishing_position + Vector2(0, -3)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	activities.casts_today = 0
	activities.panel.open(&"fishing")
	activities.start_fishing()
	await create_timer(0.4).timeout
	activities.tick_fishing(4.0)
	activities._process(0.0)
	await _shot("fishing")
	activities.panel.close()
	main.get_node("Systems/CommunityCenter").from_dict({"stage": 3})
	camera.set_view_zoom(camera.minimum_view_zoom(), true, false)
	player.global_position = Vector2(320, 240)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	await _shot("community")
	var tiller: Node = main.get_node("Farm/Tiller")
	var potato: CropData = load("res://data/crops/potato.tres")
	var blueberry: CropData = load("res://data/crops/blueberry.tres")
	tiller._spawn_crop(Vector2i(18, 6), potato, 2, false)
	tiller._spawn_crop(Vector2i(19, 6), blueberry, 3, false)
	var regrowing: Crop = tiller._spawn_crop(Vector2i(20, 6), blueberry, 3, false)
	regrowing.regrow_after_harvest()
	player.global_position = Vector2(312, 124)
	camera.set_view_zoom(2.0, true, false)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	await _shot("crops")
