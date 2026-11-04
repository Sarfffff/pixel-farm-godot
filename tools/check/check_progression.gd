extends SceneTree
## 新循环回归：真实采集、订单期限、引导、升级、三格浇水、旧档兼容。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[progression] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	# 不依赖渲染帧率：完整一分钟，30/60/144 FPS 的结果一致。
	for fps: int in [30, 60, 144]:
		var clock := preload("res://scripts/time/time_system.gd").new()
		# 速率可配（默认星露谷 10 分钟 / 7 秒），期望值按当前速率算，不写死
		var expected: int = 360 + int(floor(60.0 * clock.minutes_per_real_second + 0.000001))
		for frame in fps * 60:
			clock._process(1.0 / fps)
		_check(clock.minutes == expected, "one minute matches the configured speed at %d FPS" % fps)
		clock.running = false
		clock._process(20.0)
		_check(clock.minutes == expected, "stopped clock does not accumulate time")
		clock.free()

	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame
	await physics_frame
	var time := _main.get_node("Systems/Time")
	var forage := get_first_node_in_group(&"forage")
	var inventory := get_first_node_in_group(&"inventory") as Inventory
	var stamina := get_first_node_in_group(&"stamina")
	var orders := get_first_node_in_group(&"orders")
	var upgrades := get_first_node_in_group(&"upgrades")
	var tutorial := get_first_node_in_group(&"tutorial")
	var tiller := get_first_node_in_group(&"farm_tiller")
	var community := get_first_node_in_group(&"community")
	var economy := get_first_node_in_group(&"economy") as Economy
	var player := get_first_node_in_group(&"player") as CharacterBody2D
	var save := get_first_node_in_group(&"save")
	var shop := _main.get_node("UI/ShopPanel")
	var weather := get_first_node_in_group(&"weather")
	weather.lock(&"sunny")
	time.running = false
	_check(forage.patches.size() == 10, "ten forage patches available on day one")
	_check(orders.item_id() == &"fiber" and orders.required() == 4, "starter order uses accessible fiber")
	# 通过玩家的真实交互入口采集，不向背包注入纤维。
	for index in 7:
		var patch: Node2D = forage.patches[index]
		player.global_position = patch.global_position + Vector2(0, 5)
		_check(not tiller._has_ground_overlay(Vector2i(patch.global_position / 16)), "forage is on open ground")
		_check(player._try_interact(), "nearby forage can be interacted with")
	_check(inventory.count_of(&"fiber") == 14, "seven gathered patches yield fourteen fiber")
	_check(stamina.value == 86, "gathering has a predictable stamina cost")
	_check(orders.deliver(), "starter order is deliverable without cheats")
	_check(inventory.count_of(&"fiber") == 10, "fiber remains for first community stage")
	var forage_snapshot: Dictionary = forage.to_dict()
	forage.from_dict(forage_snapshot)
	_check(forage.patches.size() == 3, "loading does not respawn collected grass")
	var old_day: int = time.day
	time.sleep()
	_check(forage.patches.size() == 6, "next day regenerates only three patches")
	forage._on_day_started(time.day)
	_check(forage.patches.size() == 6, "repeated day signal cannot duplicate forage")
	_check(orders.has_order(), "completed order is replaced the next morning")
	var order_snapshot: Dictionary = orders.to_dict()
	for index in 3:
		time.sleep()
	_check(orders.to_dict() == order_snapshot, "unfinished crop order survives three nights")
	time.sleep()
	_check(orders.to_dict() == order_snapshot and orders.days_left() == 1, "order remains valid on its last day")
	time.sleep()
	_check(int(orders.order[&"day"]) == time.day and time.day == old_day + 6, "expired order refreshes on following day")

	# 金币/材料不足时不动余额，足够后只允许升级一次。
	var coins_before: int = economy.coins
	_check(not upgrades.purchase(), "upgrade is rejected without its materials")
	_check(economy.coins == coins_before and upgrades.watering_level == 0, "failed upgrade does not spend coins")
	inventory.add_item(&"wood", 6)
	inventory.add_item(&"stone", 4)
	_check(not upgrades.purchase(), "insufficient coins reject a fully stocked upgrade")
	_check(inventory.count_of(&"wood") == 6 and inventory.count_of(&"stone") == 4, "rejected upgrade retains materials")
	economy.earn(600)
	coins_before = economy.coins
	_check(upgrades.purchase(), "stocked upgrade succeeds")
	_check(economy.coins == coins_before - 600 and inventory.count_of(&"wood") == 0 and inventory.count_of(&"stone") == 0, "upgrade deducts exact cost")
	_check(not upgrades.purchase(), "upgraded tool cannot be charged twice")

	# 从播种到首次出售完成引导；三格都只消耗一次水壶体力。
	tutorial.from_dict({})
	player.global_position = Vector2(312, 136)
	player._facing = &"up"
	var cell := Vector2i(19, 7)
	for target: Vector2i in [cell, cell + Vector2i.LEFT, cell + Vector2i.RIGHT]:
		tiller._on_use_requested(&"seeds", target)
	_check(tutorial.step == 2, "planting existing soil skips optional tilling lesson")
	stamina.refill()
	tiller._on_use_requested(&"watering_can", cell)
	_check(stamina.value == 97, "three-cell watering consumes three stamina once")
	for target: Vector2i in tiller.watering_cells(cell):
		_check(tiller._crops[target].watered, "all three crops receive water")
	_check(tutorial.step == 3, "successful watering advances guide")
	var after_water: int = stamina.value
	tiller._on_use_requested(&"watering_can", cell)
	_check(stamina.value == after_water, "invalid repeat watering costs nothing")
	time.sleep()
	_check(tutorial.step == 4, "sleep advances guide to daily care")
	for index in 2:
		tiller._on_use_requested(&"watering_can", cell)
		time.sleep()
	_check(tiller._crops[cell].is_mature(), "three cared-for nights mature the crop")
	tiller.interact(cell)
	_check(tutorial.step == 5 and inventory.count_of(&"carrot") == 1, "harvest advances to first sale")
	shop._sell(&"carrot", 25, 1)
	_check(tutorial.step == 7, "first sale with an existing upgrade starts reinvestment")
	# 普通存档往返包含所有新字段；旧档缺字段有默认值。
	var snapshot: Dictionary = save.collect()
	upgrades.from_dict({})
	tutorial.from_dict({})
	save.apply(snapshot)
	_check(upgrades.watering_level == 1 and tutorial.step == 7, "upgrade and tutorial survive full save roundtrip")
	_check(forage.to_dict() == snapshot[&"forage"], "forage state survives full save roundtrip")
	var old_save: Dictionary = snapshot.duplicate(true)
	for key: String in ["upgrades", "tutorial", "forage"]:
		old_save.erase(key)
	save.apply(old_save)
	_check(upgrades.watering_level == 0 and tutorial.step == 0 and forage.patches.size() == 10, "old saves initialize new systems safely")
	# 真正补通第一阶段的材料路径。
	inventory.add_item(&"wood", 15)
	_check(community.can_donate(), "naturally gathered fiber satisfies community requirement")
	# 凌晨两点累倒（星露谷规则）：不弹面板，自动进下一天、扣 10% 金币、体力只回一半。
	player.set_input_locked(false)
	await process_frame
	time.running = true
	time.minutes = time.CLOSE_MINUTES - 1
	time.reset_clock()
	stamina.refill()
	var coins_before_passout: int = economy.coins
	var day_before: int = time.day
	# 时间速率可配，给足 1 秒才会推进到累倒线
	time._process(1.0)
	var summary := _main.get_node("UI/DaySummary")
	_check(not summary.visible, "02:00 does not open a prompt panel")
	# 累倒流程：渐黑 0.6 + 停留 1.0 + 渐亮 0.5 + 罚款提示 1.4
	await create_timer(4.2).timeout
	_check(time.day == day_before + 1, "passing out advances to the next day")
	# 醒来后时钟继续走，等待期间会推进几分钟
	_check(
		time.minutes >= time.START_MINUTES and time.minutes <= time.START_MINUTES + 30,
		"waking up resets the clock to about 06:00 (got %d)" % time.minutes
	)
	var expected_fine: int = mini(int(floor(float(coins_before_passout) * 0.1)), 1000)
	_check(
		economy.coins == coins_before_passout - expected_fine,
		"passing out costs 10%% gold (%d -> %d, expected fine %d)" % [
			coins_before_passout, economy.coins, expected_fine
		]
	)
	_check(
		stamina.value == stamina.MAX_VALUE / 2,
		"passing out leaves half stamina (%d)" % stamina.value
	)
	_check(not bool(player.get("input_locked")), "player control returns after passing out")
	_check(not summary.visible, "the summary stays closed after passing out")
	_main.queue_free()
	await process_frame
	await process_frame
	print("[progression] clock, forage, deadlines, guide, upgrades, saves, bedtime; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
