extends SceneTree
## 实际物品与结算链：初始种子→收成出售→采木石→升级→买种再生产→存档恢复。
## 不注入金币、种子、木材或石头；加 -- --preview 可输出真实渲染截图。

var _failures: int = 0
var _main: Node2D
var _finished: bool = false
const CELLS: Array[Vector2i] = [Vector2i(18, 7), Vector2i(19, 7), Vector2i(20, 7), Vector2i(18, 6), Vector2i(19, 6)]


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		printerr("[basic_loop] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	await _exercise_loop()
	_check(_finished, "entire loop reached its last assertion")
	if is_instance_valid(_main):
		_main.queue_free()
	await process_frame
	await process_frame
	print("[basic_loop] %s; %d failures" % ["PASS" if _failures == 0 else "FAIL", _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _exercise_loop() -> void:
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	await physics_frame
	var tiller := _main.get_node("Farm/Tiller")
	var inventory := _main.get_node("Systems/Inventory") as Inventory
	var economy := _main.get_node("Systems/Economy") as Economy
	var tutorial := _main.get_node("Systems/Tutorial")
	var upgrades := _main.get_node("Systems/Upgrades")
	var time := _main.get_node("Systems/Time")
	var save := _main.get_node("Systems/Save")
	var shop := _main.get_node("UI/ShopPanel")
	var player := _main.get_node("Farm/World/Player")
	_main.get_node("Systems/Weather").lock(&"sunny")
	time.running = false
	_check(economy.coins == 500 and inventory.count_of(&"carrot_seeds") == 5, "normal starting resources")
	shop.item_sold.emit(&"egg", 1)
	_check(tutorial.step == 0, "selling eggs cannot skip farming lessons")
	for cell: Vector2i in CELLS:
		tiller._on_use_requested(&"seeds", cell)
	_check(inventory.count_of(&"carrot_seeds") == 0 and tutorial.step == 2, "five starting seeds are planted")
	for night: int in 3:
		for cell: Vector2i in CELLS:
			tiller._on_use_requested(&"watering_can", cell)
		time.sleep()
	for cell: Vector2i in CELLS:
		_check(tiller._crops.has(cell) and tiller._crops[cell].is_mature(), "first crop matures normally")
		tiller.interact(cell)
	_check(tutorial.step == 5 and inventory.count_of(&"carrot") == 5, "first actual harvest")
	_check(shop._sell(&"carrot", inventory.definition(&"carrot").sell_price, 5) == 5, "first crop sells")
	_check(economy.coins == 625 and tutorial.step == 6, "harvest funds next upgrade")
	await _preview("upgrade")
	# 从场上实际道具获取升级材料，命中入口同时扣除体力。
	for tree: Node2D in get_nodes_in_group(&"choppable"):
		if inventory.count_of(&"wood") >= 6:
			break
		var cell := Vector2i((tree.global_position - Vector2(0, 3)) / 16.0)
		for hit: int in int(tree.hits_required):
			tiller._on_action_started(&"axe", cell)
			tiller._on_use_requested(&"axe", cell)
		await create_timer(0.55).timeout
	for rock: Node2D in get_nodes_in_group(&"breakable_rock"):
		if inventory.count_of(&"stone") >= 4:
			break
		var cell := Vector2i((rock.global_position - Vector2(0, 4)) / 16.0)
		for hit: int in int(rock.hits_remaining):
			tiller._on_action_started(&"stone_pickaxe", cell)
			tiller._on_use_requested(&"stone_pickaxe", cell)
		await create_timer(0.25).timeout
	_check(inventory.count_of(&"wood") >= 6 and inventory.count_of(&"stone") >= 4, "world supplies the upgrade materials")
	_check(upgrades.purchase(), "earned money and gathered materials buy upgrade")
	_check(economy.coins == 25 and tutorial.step == 7, "upgrade starts another production round")
	_check(not upgrades.purchase() and economy.coins == 25, "upgrade cannot charge twice")
	_check(shop._buy(&"carrot_seeds", inventory.definition(&"carrot_seeds").buy_price, 3) == 3, "remaining money buys three seeds")
	_check(economy.coins == 1 and tutorial.bought_again, "reinvestment is funded without injected money")
	# 收获、砍树、碎石会用尽当天体力，正常过夜后再开始第二轮。
	time.sleep()
	for index: int in 3:
		tiller._on_use_requested(&"seeds", CELLS[index])
	_check(inventory.count_of(&"carrot_seeds") == 0 and tutorial.planted_again.size() == 3, "new purchased seeds create three tracked crops")
	player._facing = &"up"
	var stamina := _main.get_node("Systems/Stamina")
	var before: int = stamina.value
	var dry_reinvestment: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	tiller._on_use_requested(&"watering_can", CELLS[1])
	_check(stamina.value == before - 3, "upgraded can waters three crops for three stamina")
	_check(tutorial.planted_again.size() == 3 and tutorial.watered_again.size() == 3, "journal counts distinct planted and watered plots")
	for index: int in 3:
		_check(tiller._crops[CELLS[index]].watered, "upgraded coverage changes actual farm state")
	await _preview("reinvest")
	time.sleep()
	# JSON 和磁盘往返，保存中途进度；runner 必须提供独立 user 目录。
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	save.use_slot(3)
	_check(save.save_game(), "mid-loop save writes to disk")
	tutorial.from_dict({})
	save.apply(snapshot)
	_check(tutorial.step == 7 and tutorial.planted_again.size() == 3 and tutorial.watered_again.size() == 3, "reinvestment survives JSON roundtrip")
	_check(save.load_game(3), "mid-loop disk save reloads")
	for night: int in 2:
		tiller._on_use_requested(&"watering_can", CELLS[1])
		time.sleep()
	for index: int in 3:
		tiller.interact(CELLS[index])
	shop.item_sold.emit(&"egg", 1)
	_check(tutorial.step == 7, "unrelated sales do not complete reinvestment")
	shop._sell(&"carrot", inventory.definition(&"carrot").sell_price, 3)
	_check(tutorial.step == 8 and economy.coins == 76, "second crop sale completes a profitable second round")
	await _preview("complete")
	var completed: Dictionary = JSON.parse_string(JSON.stringify(save.collect()))
	save.apply(completed)
	_check(tutorial.step == 8, "completed loop persists")
	tutorial._on_item_sold(&"carrot", 1)
	_check(tutorial.step == 8, "later sales do not reset completed guidance")
	# 雨水替代人工浇水时，不得卡在已成熟作物的浇水目标。
	save.apply(dry_reinvestment)
	_main.get_node("Systems/Weather").lock(&"rainy")
	time.sleep()
	_check(tutorial.watered_again.size() == 3, "rain waters and advances all three tracked plots")
	save.apply(completed)
	# 旧档只有 step=6 时保留升级，不要求重新购买。
	tutorial.from_dict({"step": 6})
	_check(tutorial.step == 7 and not tutorial.bought_again, "old completed guide migrates to reinvestment")
	# 当前季节不可种的种子不扣款，春末订单不要求刚播种来不及收的作物。
	var gold_before: int = economy.coins
	_check(shop._buy(&"tomato_seeds", 12, 1) == 0 and economy.coins == gold_before, "out-of-season seed purchase retains money")
	var orders := _main.get_node("Systems/Orders")
	_check(not orders._obtainable_for_order(&"tomato"), "spring orders exclude unavailable summer produce")
	time.day = 28
	_check(not orders._obtainable_for_order(&"carrot"), "last-day orders cannot demand new multi-day crops")
	_check(orders._obtainable_for_order(&"egg"), "daily eggs remain an accessible order source")
	save.apply(completed)
	_finished = true


func _preview(label: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = "user://basic_loop_%s.png" % label
	var error: Error = root.get_texture().get_image().save_png(output)
	_check(error == OK, "preview saved")
	print("[basic_loop] preview: " + ProjectSettings.globalize_path(output))
