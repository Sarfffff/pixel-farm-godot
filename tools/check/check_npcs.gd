extends SceneTree

const ART: String = "res://assets/generated/characters/npcs_v1/"
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
		_check(sprite.hframes == 4 and sprite.frame == 0, "four poses, front default")
		_check(sprite.offset == Vector2(0, -8), "foot origin matches player")
		_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "nearest filtering")
		_check(sprite.texture != null and sprite.texture.get_size() == Vector2(128, 32), "direction sheet loads")
		sprite.free()
	var main_packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_check(main_packed != null, "main scene loads")
	if main_packed == null:
		quit(1)
		return
	var main: Node2D = main_packed.instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var boss: Sprite2D = main.get_node_or_null("Farm/World/Shopkeeper") as Sprite2D
	_check(boss != null, "shopkeeper placed in world")
	# 老板接管商店后，地上的钱袋子应该移除
	_check(main.get_node_or_null("Farm/World/ShopStand") == null, "coin sack removed from the map")
	if boss != null:
		var player: CharacterBody2D = main.get_node("Farm/World/Player") as CharacterBody2D
		var dialogue: Control = main.get_node("UI/DialoguePanel") as Control
		var shop: Control = main.get_node("UI/ShopPanel") as Control
		player.global_position = boss.global_position + Vector2(0, 14)
		_check(bool(boss.call("player_in_range", player)), "standing in front of the keeper is in range")
		player.global_position = boss.global_position + Vector2(0, 90)
		_check(not bool(boss.call("player_in_range", player)), "walking away leaves the interaction range")
		# 站到侧面也不转向：老板固定朝下守着摊位
		player.global_position = boss.global_position + Vector2(18, 0)
		await physics_frame
		await physics_frame
		_check(boss.frame == 0, "keeper stays facing down instead of turning")
		player.global_position = boss.global_position + Vector2(0, 14)
		boss.call("interact", Vector2i.ZERO)
		_check(dialogue.visible, "talking to the keeper opens the dialogue")
		_check(not shop.visible, "shop stays closed until you pick the option")
		dialogue.call("_choose", &"shop")
		_check(shop.visible and not dialogue.visible, "shop opens from the dialogue option")
		shop.call("set_open", false)
		var body := boss.get_node_or_null("Body") as StaticBody2D
		_check(body != null and body.get_node_or_null("Feet") != null, "keeper has a feet collider")
	main.queue_free()
	await process_frame
	print("[npcs] 4 characters, 16 poses, shop integration; %d failures" % _failures)
	quit(0 if _failures == 0 else 1)
