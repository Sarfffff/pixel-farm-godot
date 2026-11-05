extends SceneTree
## 进出房屋 + 睡觉流程回归。
##
## 覆盖：黑幕节点、门口淡入淡出进出屋、室内家具碰撞与床位、睡前结算、
## 过夜后角色在床边醒来并解锁输入、存档坐标仍在农场侧。
## --headless --path . --script res://tools/check/check_house.gd [-- --preview]

const MAIN_SCENE := "res://scenes/main.tscn"
const PREVIEW_PATH := "res://docs/screenshots/house-interior.png"
## 门过渡：渐黑 0.22 + 停留 0.06 + 渐亮 0.30，留点余量
const DOOR_WAIT: float = 0.9
## 睡觉：渐黑 0.45 + 停留 0.9 + 渐亮 0.5
const SLEEP_WAIT: float = 2.2

var _failures: int = 0
var _preview: bool = false


func _init() -> void:
	_preview = "--preview" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[house] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	var main := load(MAIN_SCENE).instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame

	var house := main.get_node_or_null("Systems/HouseManager")
	var door := main.get_node_or_null("Farm/World/CottageDoor") as Node2D
	var farm := main.get_node("Farm") as Node2D
	var player := main.get_node("Farm/World/Player") as CharacterBody2D
	var camera := main.get_node("Camera") as Camera2D
	var fade := main.get_node_or_null("ScreenFade")
	_check(house != null, "house manager exists")
	_check(door != null, "cottage door exists")
	_check(fade != null, "screen fade layer exists")
	if house == null or door == null:
		_finish()
		return

	_check(not bool(house.call("is_inside")), "starts outdoors")
	_check(farm.visible, "farm visible outdoors")
	_check(String(door.call("hint")).contains("进屋"), "door hints entering")

	# —— 进屋：门口按 E，过渡后农场隐藏、玩家进室内 ——
	player.global_position = door.global_position + Vector2(0, 10)
	var outside_position: Vector2 = player.global_position
	_check(bool(door.call("player_in_range", player)), "standing at the door is in range")
	door.call("interact", Vector2i.ZERO)
	await create_timer(DOOR_WAIT).timeout

	var interior := main.get_node_or_null("HouseInterior") as Node2D
	_check(interior != null, "interior instance created")
	_check(bool(house.call("is_inside")), "entering sets indoors")
	_check(not farm.visible, "farm hidden indoors")
	_check(interior != null and interior.visible, "interior visible")
	_check(not bool(fade.call("is_black")), "fade clears after entering")
	_check(not bool(player.get("input_locked")), "player unlocked after entering")
	var tint := main.get_node_or_null("DayNightTint") as CanvasModulate
	_check(tint != null, "day-night tint exists")
	_check(
		tint != null and tint.color.is_equal_approx(Color(0.97, 0.93, 0.85)),
		"interior stays lit indoors"
	)
	if interior == null:
		_finish()
		return

	# 玩家要进 Y 排序层，否则会被地毯、椅子盖住
	var props := interior.get_node_or_null("Props") as Node2D
	_check(
		props != null and player.get_parent() == props,
		"player reparented into the sorted props layer"
	)
	var spawn := interior.get_node_or_null("Spawn") as Node2D
	_check(spawn != null, "interior has a spawn marker")
	if spawn != null:
		var expected: Vector2 = interior.global_position + spawn.position
		_check(player.global_position.distance_to(expected) < 2.0, "player lands on the spawn")

	# —— 室内家具与床 ——
	_check(interior.get_node_or_null("Floor") != null, "interior has floor layer")
	_check(interior.get_node_or_null("Walls") != null, "interior has wall layer")
	var bed_spot := interior.get_node_or_null("BedSpot") as Node2D
	var wake_spot := interior.get_node_or_null("WakeSpot") as Node2D
	_check(bed_spot != null, "interior has a bed spot to sleep on")
	_check(wake_spot != null, "interior has a wake spot")
	var bed_body := interior.get_node_or_null("Props/SingleBed/Body") as StaticBody2D
	_check(bed_body != null, "bed blocks the player (furniture collision)")
	var wall_body := interior.get_node_or_null("WallBody") as StaticBody2D
	_check(wall_body != null, "room walls have collision")
	_check(
		wall_body != null and wall_body.get_child_count() >= 4,
		"wall collision covers all four sides"
	)
	_check(
		interior.get_node_or_null("Props") != null and interior.get_node("Props").get_child_count() >= 20,
		"interior is furnished (>=20 props)"
	)
	_check(interior.get_node_or_null("ExitDoor") != null, "interior has an exit door")
	# 室内木箱：接到农场的 24 格仓库面板
	var chest := interior.get_node_or_null("Chest") as Node2D
	_check(chest != null, "interior has a storage chest")
	if chest != null:
		_check(String(chest.call("hint")).contains("木箱"), "chest hints opening")
		player.global_position = chest.global_position + Vector2(0, 10)
		_check(bool(chest.call("player_in_range", player)), "standing by the chest is in range")
		chest.call("interact", Vector2i.ZERO)
		await process_frame
		var storage_panel := main.get_node_or_null("UI/FarmActivitiesPanel") as Control
		_check(storage_panel != null and storage_panel.visible, "chest opens the storage panel")
		if storage_panel != null:
			_check(String(storage_panel.get("mode")) == "storage", "panel opens in storage mode")
			storage_panel.call(&"close")
			await process_frame

	if _preview:
		await _save_preview()

	# —— 睡觉流程：只有贴着床才能睡；白天小睡到傍晚，晚上才过夜 ——
	var summary := main.get_node("UI/DaySummary") as Control
	var time := main.get_node("Systems/Time")
	var day_before: int = int(time.get("day"))
	var wake_world: Vector2 = interior.global_position + (wake_spot.position if wake_spot != null else Vector2.ZERO)
	if bed_spot != null:
		_check(String(bed_spot.call("hint")).contains("睡觉"), "bed spot hints sleeping")
		player.global_position = bed_spot.global_position + Vector2(0, 6)
		_check(bool(bed_spot.call("player_in_range", player)), "standing by the bed is in range")
		player.global_position = bed_spot.global_position + Vector2(0, 60)
		_check(not bool(bed_spot.call("player_in_range", player)), "walking away leaves the bed range")
		player.global_position = bed_spot.global_position + Vector2(0, 6)

		# 白天（06:00）：小睡到 20:00，日期不变
		bed_spot.call("interact", Vector2i.ZERO)
		await process_frame
		_check(summary.visible, "bed opens the night summary")
		_check(bool(player.get("input_locked")), "summary locks the player")
		var nap_button := summary.get_node_or_null("%SleepButton") as Button
		_check(nap_button != null and nap_button.text.contains("小睡"), "daytime summary offers a nap")
		if _preview: await _save_summary_preview("nap")
		summary.call("_sleep")
		await create_timer(SLEEP_WAIT).timeout

		_check(int(time.get("day")) == day_before, "a daytime nap keeps the same day")
		# 醒来后输入解锁、时钟重新走，断言放宽到十几分钟误差内
		var nap_minutes: int = int(time.get("minutes"))
		_check(
			nap_minutes >= 20 * 60 and nap_minutes <= 20 * 60 + 15,
			"a daytime nap wakes you around 20:00 (got %d)" % nap_minutes
		)
		_check(not summary.visible, "summary closes after napping")
		_check(player.visible, "player visible again after napping")
		_check(not bool(player.get("input_locked")), "player unlocked after napping")
		_check(not bool(fade.call("is_black")), "fade clears after napping")
		_check(player.global_position.distance_to(wake_world) < 2.0, "player gets up beside the bed")

		# 晚上（20:00）：过夜进入下一天
		time.set("minutes", 20 * 60)
		time.call("reset_clock")
		player.global_position = bed_spot.global_position + Vector2(0, 6)
		bed_spot.call("interact", Vector2i.ZERO)
		await process_frame
		var night_button := summary.get_node_or_null("%SleepButton") as Button
		_check(night_button != null and night_button.text.contains("睡觉"), "night summary offers sleeping")
		if _preview: await _save_summary_preview("night")
		summary.call("_sleep")
		await create_timer(SLEEP_WAIT).timeout

		_check(int(time.get("day")) == day_before + 1, "sleeping at night advances the day")
		var wake_minutes: int = int(time.get("minutes"))
		_check(
			wake_minutes >= 6 * 60 and wake_minutes <= 6 * 60 + 15,
			"waking resets the clock to about 06:00 (got %d)" % wake_minutes
		)
		_check(not summary.visible, "summary closes after sleeping")
		_check(player.visible, "player visible again after waking")
		_check(not bool(player.get("input_locked")), "player unlocked after waking")
		_check(not bool(fade.call("is_black")), "fade clears after waking")
		if wake_spot != null:
			_check(
				player.global_position.distance_to(wake_world) < 2.0,
				"player wakes beside the bed (%s vs %s)" % [player.global_position, wake_world]
			)

	# 存档要记门外坐标
	_check(
		(house.call("save_position") as Vector2).distance_to(outside_position) < 2.0,
		"save position stays on the farm side"
	)
	_check(camera.world_bounds.size.x < 500.0, "camera bounds shrink to the room")

	# —— 出门 ——
	var exit_door := interior.get_node_or_null("ExitDoor") as Node2D
	player.global_position = exit_door.global_position + Vector2(0, -6)
	_check(bool(exit_door.call("player_in_range", player)), "standing inside the door is in range")
	exit_door.call("interact", Vector2i.ZERO)
	await create_timer(DOOR_WAIT).timeout

	_check(not bool(house.call("is_inside")), "exiting sets outdoors")
	_check(farm.visible, "farm visible again")
	_check(not interior.visible, "interior hidden after leaving")
	_check(player.get_parent() == farm.get_node("World"), "player reparented back to the farm world")
	_check(
		player.global_position.distance_to(outside_position) < 24.0,
		"player returns near the door (%s vs %s)" % [player.global_position, outside_position]
	)
	_check(camera.world_bounds.size.x > 600.0, "camera bounds restored to the farm")
	_check(not bool(fade.call("is_black")), "fade clears after leaving")
	_check(
		tint != null and not tint.color.is_equal_approx(Color(0.97, 0.93, 0.85)),
		"outdoor tint comes back after leaving"
	)

	# —— 换栋建筑：商店门进的是另一套室内，农舍那间保持隐藏 ——
	var shop_door := main.get_node_or_null("Farm/World/ShopDoor") as Node2D
	_check(shop_door != null, "shop door exists on the farm")
	if shop_door != null:
		player.global_position = shop_door.global_position + Vector2(0, 10)
		shop_door.call("interact", Vector2i.ZERO)
		await create_timer(DOOR_WAIT).timeout
		var shop_room := main.get_node_or_null("ShopInterior") as Node2D
		_check(shop_room != null, "shop door creates its own interior")
		_check(shop_room != null and shop_room.visible, "shop interior visible")
		_check(shop_room != null and shop_room != interior, "shop is a different room from the house")
		_check(not interior.visible, "house interior stays hidden while in the shop")
		_check(
			shop_room == null or player.get_parent() == shop_room.get_node_or_null("Props"),
			"player lands in the shop's props layer"
		)
		var shop_exit := shop_room.get_node_or_null("ExitDoor") as Node2D
		if shop_exit != null:
			player.global_position = shop_exit.global_position + Vector2(0, -6)
			shop_exit.call("interact", Vector2i.ZERO)
			await create_timer(DOOR_WAIT).timeout
		_check(not bool(house.call("is_inside")), "exiting the shop works too")

	main.queue_free()
	await process_frame
	_finish()


## 有窗口运行时截一张室内图，便于人工核对家具与床的位置。
func _save_summary_preview(mode: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "user://summary_%s.png" % mode
	_check(root.get_texture().get_image().save_png(path) == OK, "summary preview renders")
	print("[house] summary preview -> " + ProjectSettings.globalize_path(path))


func _save_preview() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_warning("[house] 无法获取视口图像，跳过预览")
		return
	if image.save_png(PREVIEW_PATH) == OK:
		print("[house] preview -> %s" % PREVIEW_PATH)


func _finish() -> void:
	if _failures == 0:
		print("[house] PASS")
	else:
		printerr("[house] FAIL，共 %d 项" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
