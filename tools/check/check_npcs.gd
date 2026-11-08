extends SceneTree

const ART: String = "res://assets/textures/characters/npcs_v1/"
const IDS: Array[String] = ["shopkeeper", "gardener", "carpenter", "fisherman"]
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[npcs] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	for id: String in IDS:
		for direction: String in DIRECTIONS:
			var image: Image = Image.load_from_file(ProjectSettings.globalize_path(ART + id + "_" + direction + ".png"))
			_check(image != null, id + " " + direction + " exists")
			if image == null:
				continue
			_check(image.get_size() == Vector2i(32, 32), "32x32 frame")
			var bounds: Rect2i = image.get_used_rect()
			_check(bounds.size.y > 0 and bounds.end.y == 24, "feet end at y=24")
			var colors: Dictionary[Color, bool] = {}
			for y: int in image.get_height():
				for x: int in image.get_width():
					var color: Color = image.get_pixel(x, y)
					_check(color.a == 0.0 or color.a == 1.0, "binary alpha")
					if color.a == 1.0:
						colors[color] = true
						_check(not (color.r > 0.9 and color.b > 0.9 and color.g < 0.2), "no magenta background")
			_check(colors.size() <= 19, "limited palette")
		var packed: PackedScene = load("res://scenes/npcs/" + id + ".tscn") as PackedScene
		_check(packed != null, id + " scene loads")
		if packed == null:
			continue
		var sprite: Sprite2D = packed.instantiate() as Sprite2D
		_check(sprite != null, "Sprite2D root")
		if sprite == null:
			continue
		_check(sprite.hframes == 3 and sprite.vframes == 4 and sprite.frame == 0, "%s has 3x4 walk poses, front default" % id)
		_check(sprite.texture != null and sprite.texture.resource_path.ends_with(id + "_walk.png"), id + " uses its walk sheet")
		_check(sprite.offset == Vector2(0, -8), "foot origin matches player")
		_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest filtering")
		var sheet: Vector2 = sprite.texture.get_size() if sprite.texture != null else Vector2.ZERO
		_check(
			sheet.x > 0.0
				and int(sheet.x) % maxi(sprite.hframes, 1) == 0
				and int(sheet.y) % maxi(sprite.vframes, 1) == 0,
			"%s sheet slices evenly (%s / %dx%d)" % [id, sheet, sprite.hframes, sprite.vframes]
		)
		sprite.free()
	var main_packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_check(main_packed != null, "main scene loads")
	if main_packed == null:
		preload("res://tools/lib/check_lifecycle.gd").finish(self, 1)
		return
	var main: Node2D = main_packed.instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	# 店主已经搬进店里：农场只留店门
	_check(main.get_node_or_null("Farm/World/Shopkeeper") == null, "keeper moved indoors")
	_check(main.get_node_or_null("Farm/World/ShopStand") == null, "coin sack removed from the map")
	var shop_door := main.get_node_or_null("Farm/World/ShopDoor") as Node2D
	_check(shop_door != null, "shop door placed in world")
	var player: CharacterBody2D = main.get_node("Farm/World/Player") as CharacterBody2D
	var dialogue: Control = main.get_node("UI/DialoguePanel") as Control
	var shop: Control = main.get_node("UI/ShopPanel") as Control
	var clock := main.get_node("Systems/Time")
	# 商店有营业时间：先把时钟拨到 10:00
	clock.set("minutes", 10 * 60)
	clock.call("reset_clock")

	var boss: Sprite2D
	if shop_door != null:
		player.global_position = shop_door.global_position + Vector2(0, 12)
		_check(bool(shop_door.call("player_in_range", player)), "standing at the shop door is in range")
		shop_door.call("interact", Vector2i.ZERO)
		await create_timer(0.9).timeout
		# 店铺有独立的室内场景（ShopInterior），不再复用农舍那间
		var interior := main.get_node_or_null("ShopInterior") as Node2D
		_check(interior != null, "shop interior loads")
		if interior != null:
			# 老板摆在室内场景的 Props 组下，按名字递归找，别写死路径。
			boss = interior.find_child("Shopkeeper", true, false) as Sprite2D
		if "--preview" in OS.get_cmdline_user_args():
			await process_frame
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			var path: String = "user://shop-interior.png"
			_check(shot != null and shot.save_png(path) == OK, "isolated shop preview is saved")
			print("[npcs] preview -> " + ProjectSettings.globalize_path(path))
	_check(boss != null, "shopkeeper stands inside the store")

	if boss != null:
		player.global_position = boss.global_position + Vector2(0, 22)
		_check(bool(boss.call("player_in_range", player)), "standing in front of the counter is in range")
		player.global_position = boss.global_position + Vector2(0, 120)
		_check(not bool(boss.call("player_in_range", player)), "walking away leaves the interaction range")
		# 站到侧面也不转向：老板固定朝下守着柜台
		player.global_position = boss.global_position + Vector2(18, 0)
		await physics_frame
		await physics_frame
		_check(boss.frame == 0, "keeper stays facing down instead of turning")
		player.global_position = boss.global_position + Vector2(0, 22)
		boss.call("interact", Vector2i.ZERO)
		_check(dialogue.visible, "talking to the keeper opens the dialogue")
		_check(not shop.visible, "shop stays closed until you pick the option")
		dialogue.call("_choose", &"shop")
		_check(shop.visible and not dialogue.visible, "shop opens from the dialogue option")
		shop.call("set_open", false)
		var body := boss.get_node_or_null("Body") as StaticBody2D
		_check(body != null and body.get_node_or_null("Feet") != null, "keeper has a feet collider")

		# 打烊时间（22:00）：只给一句提示，货架不开
		clock.set("minutes", 22 * 60)
		clock.call("reset_clock")
		_check(not bool(boss.call("is_open")), "shop reports closed after hours")
		_check(String(boss.call("hint")).contains("打烊"), "hint mentions closing time")
		player.global_position = boss.global_position + Vector2(0, 22)
		boss.call("interact", Vector2i.ZERO)
		_check(dialogue.visible, "keeper still talks after hours")
		_check(not shop.visible, "shop does not open after hours")
		var line := dialogue.get_node("%Text") as Label
		_check(line != null and line.text.contains("打烊"), "closed line is shown after hours")
		dialogue.call("close")

	await _check_navigation(main)
	_check_walk_animations(main)
	await _check_villager_dialogue(main)
	main.queue_free()
	await process_frame
	print("[npcs] 4 characters, 12 directional walk cycles, idle/dialogue/resume, shop integration; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


## 网格寻路：农场有 Nav 节点、可达路径、水面与边界不可走。
func _check_navigation(main: Node2D) -> void:
	var nav := main.get_node_or_null("Farm/Nav")
	_check(nav != null, "farm has a Nav node")
	if nav == null:
		return
	await physics_frame
	await physics_frame
	var path: Array = nav.call("find_path_cells", Vector2(312, 248), Vector2(456, 280))
	_check(path.size() > 2, "path between gardener and fisherman exists (%d cells)" % path.size())
	_check(not bool(nav.call("is_walkable", Vector2i(29, 21))), "pond cell is not walkable")
	_check(not bool(nav.call("is_walkable", Vector2i(0, 0))), "map border is not walkable")
	_check(bool(nav.call("is_walkable", Vector2i(20, 16))), "open grass is walkable")


## 用真实村民节点推进移动，避免只检查素材存在却漏掉运行时没有播放动画。
func _check_walk_animations(main: Node2D) -> void:
	var directions: Array[Vector2] = [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]
	var dialogue := main.get_node("UI/DialoguePanel") as Control
	for node_name: String in ["Gardener", "Carpenter", "Fisherman"]:
		var npc := main.get_node("Farm/World/" + node_name) as VillageNpc
		var original_position: Vector2 = npc.global_position
		npc.set_physics_process(false)
		for row: int in directions.size():
			npc.global_position = original_position
			npc._path = PackedVector2Array([original_position + directions[row] * 40.0])
			npc._path_index = 0
			npc._wait_left = 0.0
			npc._stop_walking()
			var columns: Dictionary = {}
			for tick: int in 60:
				npc._physics_process(1.0 / 60.0)
				columns[npc.frame_coords.x] = true
				_check(npc.frame_coords.y == row, "%s faces direction %d" % [node_name, row])
			_check(columns.size() == 3, "%s animates all three columns in direction %d" % [node_name, row])
			_check(npc.is_walking() and npc.global_position != original_position, node_name + " animates while actually moving")
			# 素材本身也必须有不同的脚部像素，防止三列全是复制的站姿。
			var sheet: Image = npc.texture.get_image()
			var idle: PackedByteArray = sheet.get_region(Rect2i(0, row * 32, 32, 32)).get_data()
			_check(idle != sheet.get_region(Rect2i(32, row * 32, 32, 32)).get_data(), node_name + " first step differs from idle")
			_check(idle != sheet.get_region(Rect2i(64, row * 32, 32, 32)).get_data(), node_name + " second step differs from idle")

		var before_dialogue: Vector2 = npc.global_position
		npc.interact(Vector2i.ZERO)
		npc._physics_process(0.2)
		_check(not npc.is_walking() and npc.frame_coords.x == 0, node_name + " returns to idle during dialogue")
		_check(npc.global_position == before_dialogue, node_name + " stands still during dialogue")
		dialogue.call("close")
		npc._physics_process(0.2)
		_check(npc.is_walking() and npc.global_position != before_dialogue, node_name + " resumes after dialogue")

		for tick: int in 120:
			npc._physics_process(1.0 / 60.0)
		_check(not npc.is_walking() and npc.frame_coords.x == 0, node_name + " stands idle on reaching destination")
		npc.global_position = original_position
		npc._path.clear()
		npc._wait_left = 0.0
		npc.set_physics_process(true)


## 村民：会走动、四向帧合法、多句对话能逐句推进。
func _check_villager_dialogue(main: Node2D) -> void:
	var gardener := main.get_node_or_null("Farm/World/Gardener") as Sprite2D
	_check(gardener != null, "gardener placed in world")
	if gardener == null:
		return
	var start: Vector2 = gardener.global_position
	await create_timer(1.4).timeout
	_check(gardener.global_position.distance_to(start) > 4.0, "gardener walks along its routine")
	_check(gardener.frame_coords.y >= 0 and gardener.frame_coords.y <= 3 and gardener.frame_coords.x <= 2, "gardener uses a valid walk frame")

	var dialogue := main.get_node("UI/DialoguePanel") as Control
	gardener.call("interact", Vector2i.ZERO)
	_check(dialogue.visible, "talking to the gardener opens the dialogue")
	var text_label := dialogue.get_node("%Text") as Label
	var first: String = text_label.text
	_check(not first.is_empty(), "dialogue shows the first line")
	dialogue.call("_choose", &"__next")
	_check(text_label.text != first, "next advances to the second line")
	dialogue.call("close")
	_check(not dialogue.visible, "dialogue closes")
