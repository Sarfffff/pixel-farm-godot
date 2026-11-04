extends SceneTree
## 正式会话中的跨区、真实工具命中、落地拾取、再生、恢复和种田兼容。

const Safety = preload("res://tools/lib/check_safety.gd")
var _main: Node2D
var _failures: int = 0
var _checks: int = 0
var _finished: bool = false


func _init() -> void:
	if not Safety.require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[region_gameplay] FAIL: " + message)


func _spawn_main() -> void:
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	await physics_frame
	_main.get_node("Systems/Time").running = false
	_main.get_node("Systems/Weather").lock(&"sunny")


func _run() -> void:
	await _exercise()
	_check(_finished, "full gameplay check reached the end")
	if is_instance_valid(_main): _main.queue_free()
	await process_frame
	await process_frame
	print("[region_gameplay] %s; %d checks; %d failures" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _find(manager: Node, kind: String) -> String:
	for id: String in manager.ledger.regions[String(manager.active_region)].objects:
		var state: Dictionary = manager.ledger.object(manager.active_region, id)
		if state.kind == kind and int(state.hits) > 0: return id
	return ""


func _approach(manager: Node, id: String) -> void:
	var node: Sprite2D = manager._sprites[String(manager.active_region)][id]
	manager.player.global_position = node.global_position + Vector2(0, 8)
	manager.player._facing = &"up"
	manager.player.velocity = Vector2.ZERO


func _exercise() -> void:
	await _spawn_main()
	var manager: Node = _main.get_node("Systems/Regions")
	var actor: CharacterBody2D = _main.get_node("Farm/World/Player")
	var field: Node = _main.get_node("Farm/Tiller")
	var clock: Node = _main.get_node("Systems/Time")
	var bag: Inventory = _main.get_node("Systems/Inventory")
	var wallet: Economy = _main.get_node("Systems/Economy")
	var save: Node = _main.get_node("Systems/Save")
	_check(manager.active_region == &"home", "new game starts on the original farm")
	_check(manager._roots.size() == 7, "six new maps and the original farm share one session")
	for region: String in manager.ledger.regions:
		for state: Dictionary in manager.ledger.regions[region].objects.values():
			_check(bag.definition(StringName(manager.ledger.rules[state.kind].item)) != null, "all resource drops are real inventory definitions")
	var nav: Node = _main.get_node("Farm/Nav")
	var sign: Node2D = _main.get_node("Farm/World/Route_farm")
	_check(not nav.find_path(actor.global_position, sign.global_position).is_empty(), "original farm gateway is reachable")
	# 先种一株并浇水，离开农场后继续走正常每日结算。
	var crop_cell := Vector2i(18, 7)
	field._on_use_requested(&"seeds", crop_cell)
	field._on_use_requested(&"watering_can", crop_cell)
	_check(field._crops.has(crop_cell), "original planting remains available")
	actor.global_position = sign.global_position + Vector2(0, 8)
	_check(actor._try_interact(), "E on a real gateway begins travel")
	await create_timer(0.6).timeout
	_check(manager.active_region == &"farm" and not actor.input_locked, "fade travel completes and releases input")
	_check(actor.get_parent() == manager._roots["farm"].get_node("World"), "the same player moves into destination y-sort layer")
	_check(not _main.get_node("Farm").visible, "original farm is hidden while exploring")
	_check(actor.interaction != field, "tool target adapter changes with current world")
	var id: String = _find(manager, "weeds")
	_check(not id.is_empty(), "farm outskirts contains collectable weeds")
	_approach(manager, id)
	var before: int = bag.count_of(&"fiber")
	_check(actor._try_interact(), "E collects a soft resource")
	_check(int(manager.ledger.object(&"farm", id).hits) == 0 and bag.count_of(&"fiber") == before, "harvest creates ground loot before inventory award")
	_check(not manager.ledger.regions["farm"].drops.is_empty(), "loot is recorded on the ground")
	_check(actor._try_interact() and bag.count_of(&"fiber") == before + 2, "a second E picks up the complete bundle")
	_check(manager.ledger.regions["farm"].drops.is_empty(), "successful pickup removes ground bundle")
	var twig: String = _find(manager, "twig")
	_approach(manager, twig)
	actor._select_tool(4)
	var hits_before: int = manager.ledger.object(&"farm", twig).hits
	actor._start_action()
	_check(not actor.is_acting and manager.ledger.object(&"farm", twig).hits == hits_before, "wrong tool cannot damage a resource")
	actor._select_tool(3)
	var farm_state: Dictionary = _main.world_objects.to_dict().duplicate(true)
	actor._start_action()
	_check(actor.is_acting, "correct tool uses normal player animation")
	_check(manager.ledger.object(&"farm", twig).hits == hits_before, "resource is intact before animation impact")
	await create_timer(0.7).timeout
	_check(manager.ledger.object(&"farm", twig).hits == 0, "tool impact depletes the actual selected resource")
	_check(_main.world_objects.to_dict() == farm_state, "external tool hit never changes original farm trees or rocks")
	_check(not manager.harvest.hit(&"farm", twig, &"axe"), "depleted resource cannot duplicate its drops")
	await _capture("ground_drop")
	var due: int = manager.ledger.object(&"farm", twig).due_day
	var drops_before: Dictionary = manager.ledger.regions["farm"].drops.duplicate(true)
	# 满包时地面物资不丢失。
	var bag_snapshot: Dictionary = bag.to_dict().duplicate(true)
	for slot: int in bag.slot_count(): bag._slots[slot] = {&"id": &"stone", &"count": 99}
	_check(not manager.harvest.pickup(&"farm", String(drops_before.keys()[0])), "full bag rejects pickup")
	_check(manager.ledger.regions["farm"].drops == drops_before, "failed pickup leaves the exact ground bundle")
	bag.from_dict(bag_snapshot)
	# 到期时站在资源脚下不会突然长出障碍；离开后下一天再生。
	while clock.day < due: clock.sleep()
	_check(manager.ledger.object(&"farm", twig).hits == 0, "resource does not regrow under the player")
	actor.global_position += Vector2(120, 0)
	clock.sleep()
	_check(manager.ledger.object(&"farm", twig).hits == 1, "blocked regeneration retries after the player leaves")
	var energy: Node = _main.get_node("Systems/Stamina")
	var energy_before: int = energy.value
	energy.value = 0
	_check(not manager.harvest.hit(&"farm", twig, &"axe") and manager.ledger.object(&"farm", twig).hits == 1, "insufficient stamina leaves resource intact")
	energy.value = energy_before
	var branch: String = _find(manager, "branch_pile")
	while int(manager.ledger.object(&"farm", branch).hits) > 0: manager.harvest.hit(&"farm", branch, &"axe")
	var branch_drop: String = ""
	for drop_id: String in manager.ledger.regions["farm"].drops:
		if drop_id.begins_with(branch + "/drop/"): branch_drop = drop_id
	_check(not branch_drop.is_empty(), "multi-item bundle is created")
	for slot: int in bag.slot_count(): bag._slots[slot] = {&"id": &"stone", &"count": 99}
	bag._slots[0] = {&"id": &"wood", &"count": 98}
	_check(not manager.harvest.pickup(&"farm", branch_drop) and bag.count_of(&"wood") == 98, "partial bundle capacity does not grant a partial pickup")
	bag.from_dict(bag_snapshot)
	drops_before = manager.ledger.regions["farm"].drops.duplicate(true)
	var tree: String = _find(manager, "oak_tree")
	_approach(manager, tree)
	var wood_before_tree: int = bag.count_of(&"wood")
	while int(manager.ledger.object(&"farm", tree).hits) > 0: manager.harvest.hit(&"farm", tree, &"axe")
	_check(actor._try_interact() and bag.count_of(&"wood") == wood_before_tree + 6, "large tree drops at its base within pickup reach")
	_check(manager.travel_to(&"quarry"), "quarry is a playable destination")
	var ore: String = _find(manager, "copper_node")
	_approach(manager, ore)
	_check(manager.harvest.hit(&"quarry", ore, &"stone_pickaxe"), "registered ore can be mined")
	var damaged: int = manager.ledger.object(&"quarry", ore).hits
	_check(damaged == 3, "partial damage is tracked")
	clock.sleep()
	_check(field._crops[crop_cell].stage == 1, "watered farm crop grows normally while player is away")
	while clock.day < due: clock.sleep()
	_check(manager.ledger.object(&"farm", twig).hits == 1, "offscreen resource regenerates on due day")
	_check(manager.ledger.regions["farm"].drops == drops_before, "regeneration preserves older unpicked ground loot")
	manager.begin_day(clock.day)
	_check(manager.ledger.regions["farm"].drops == drops_before, "repeated new-day call cannot create more loot")
	var expected_bag: Dictionary = bag.to_dict().duplicate(true)
	var expected_coins: int = wallet.coins
	save.use_slot(3)
	_check(save.save_game(), "complete cross-region state saves to disk")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	for iteration: int in 3:
		save.apply(snapshot)
		_check(manager.active_region == &"quarry" and manager.ledger.object(&"quarry", ore).hits == damaged, "repeated JSON restore preserves region and partial damage")
		_check(manager.ledger.regions["farm"].drops == drops_before, "repeated restore does not duplicate ground loot")
		_check(bag.to_dict() == expected_bag and wallet.coins == expected_coins, "restore grants no extra inventory or money")
	# 用全新Main重建，再读真实测试槽。
	_main.queue_free()
	await process_frame
	await process_frame
	await _spawn_main()
	manager = _main.get_node("Systems/Regions")
	save = _main.get_node("Systems/Save")
	_check(save.load_game(3), "fresh game session reloads disk save")
	_check(manager.active_region == &"quarry" and manager.ledger.object(&"quarry", ore).hits == damaged, "fresh session restores active map and resource damage")
	_check(manager.ledger.regions["farm"].drops == drops_before, "unloaded map loot survives a full restart")
	_check(_main.get_node("Systems/Inventory").to_dict() == expected_bag, "inventory survives a full restart")
	await _capture("quarry_restored")
	for area: String in ["farm", "village", "forest", "wetland", "quarry", "beach", "home"]:
		_check(manager.travel_to(StringName(area)), "all new areas and home can be entered")
	_check(_main.get_node("Farm").visible and manager.player.interaction == _main.get_node("Farm/Tiller"), "return restores farm visibility and cultivation target")
	var house: Node = _main.get_node("Systems/HouseManager")
	house.enter_house(load("res://scenes/world/house_interior.tscn"))
	_check(house.is_inside(), "original farmhouse entry still works after exploration")
	house.exit_house()
	_check(not house.is_inside(), "original farmhouse exit still works")
	manager.travel_to(&"farm")
	_check(manager.harvest.pickup(&"farm", String(drops_before.keys()[0])), "saved ground resource can still be picked up")
	manager.travel_to(&"home")
	var wood_value: int = _main.get_node("Systems/Inventory").definition(&"wood").sell_price
	var gold_before_sale: int = _main.get_node("Systems/Economy").coins
	_check(_main.get_node("Systems/Trade").sell(&"wood", 1) == 1, "gathered resource sells through the existing trade service")
	_check(_main.get_node("Systems/Economy").coins == gold_before_sale + wood_value, "resource sale uses original wallet and item price")
	# 旧v1/v2文件没有regions字段，回到原农场且保留其经营数据。
	var old: Dictionary = snapshot.duplicate(true)
	old.erase("regions")
	old.version = 1
	save.apply(old)
	_check(manager.active_region == &"home" and manager.player.interaction == _main.get_node("Farm/Tiller"), "old save defaults safely to the original farm")
	_check(_main.get_node("Farm/Tiller")._crops.has(crop_cell), "old save keeps planted crops")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.regions = {"current": "invalid", "position": ["bad", null], "resources": {"areas": {"farm": {"objects": false, "drops": {"bad": {"item": "axe", "count": 99, "cell": [0, 0]}}}}}}
	save.apply(malformed)
	_check(manager.active_region == &"home", "invalid region and position use safe defaults")
	_check(manager.ledger.regions["farm"].drops.is_empty(), "invalid drop records are not converted into items")
	# 外出累倒必须先回原农场，再走原有罚款和半体力醒来流程。
	manager.travel_to(&"forest")
	await _capture("forest")
	_main.get_node("Systems/Time").day_over.emit()
	await create_timer(4.6).timeout
	_check(manager.active_region == &"home" and _main.get_node("Farm").visible, "passing out away from home returns to the actual farm")
	_check(manager.player.get_parent() == _main.get_node("Farm/World") and not manager.player.input_locked, "pass-out recovery restores player world and input")
	_finished = true


func _capture(name: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	for frame: int in 16: await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://regions_%s.png" % name
	_check(root.get_texture().get_image().save_png(path) == OK, "window capture saved")
	print("[region_gameplay] capture: " + ProjectSettings.globalize_path(path))
