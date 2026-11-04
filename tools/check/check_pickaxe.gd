extends SceneTree

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ROCK: PackedScene = preload("res://scenes/world/props/rock.tscn")
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]

var _main: Node2D
var _world: Node2D
var _player: CharacterBody2D
var _sprite: AnimatedSprite2D
var _tiller: Node2D
var _inventory: Inventory
var _failures: int = 0
var _impacts: int = 0
var _impact_frame: int = -1
var _impact_cell: Vector2i


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[pickaxe] FAIL: " + message)


func _run() -> void:
	_main = MAIN.instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_world = _main.get_node("Farm/World") as Node2D
	_player = _world.get_node("Player") as CharacterBody2D
	_tiller = _main.get_node("Farm/Tiller") as Node2D
	_sprite = _player.get_node("Sprite") as AnimatedSprite2D
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	_main.get_node("Systems/Time").running = false
	_player.use_requested.connect(_on_impact)
	await physics_frame
	await physics_frame
	await create_timer(0.2).timeout
	_check_frames()
	_check_input()
	await _check_four_directions()
	await _check_full_bag()
	await _check_target_lock()
	await _check_real_rock_and_save()
	_main.queue_free()
	await process_frame
	print("[pickaxe] %s; %d failures" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _check_frames() -> void:
	var frames: SpriteFrames = _sprite.sprite_frames
	_check(frames.get_animation_names().size() == 64, "24 original plus 40 held player animations")
	for direction: StringName in DIRECTIONS:
		var action: StringName = StringName("stone_pickaxe_%s" % direction)
		_check(frames.has_animation(action), "pickaxe action exists: " + action)
		_check(frames.get_frame_count(action) == 6 and not frames.get_animation_loop(action), "six independent non-looping frames: " + action)
		var unique: Dictionary[String, bool] = {}
		for phase: int in 6:
			var atlas: AtlasTexture = frames.get_frame_texture(action, phase) as AtlasTexture
			_check(atlas != null, "atlas frame exists")
			if atlas == null:
				continue
			_check(atlas.atlas.resource_path == "res://assets/generated/characters/stone_pickaxe_actions_v1.png", "does not reuse hoe or axe art")
			var image: Image = atlas.get_image()
			_check(image.get_size() == Vector2i(32, 32), "32px action frame")
			_check(image.get_used_rect().size != Vector2i.ZERO, "frame is not empty")
			unique[image.get_data().hex_encode()] = true
			for y: int in 32:
				for x: int in 32:
					var alpha: float = image.get_pixel(x, y).a
					_check(alpha == 0.0 or alpha == 1.0, "binary action alpha")
		_check(unique.size() >= 5, "distinct windup, overhead, strike and recovery poses")
	var icon: Texture2D = load("res://assets/generated/items/stone_pickaxe.png") as Texture2D
	_check(icon != null and icon.get_size() == Vector2(16, 16), "16px independent tool icon")


func _check_input() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_5
	event.pressed = true
	_player._unhandled_input(event)
	_check(_player.current_tool == &"stone_pickaxe", "5 selects pickaxe")
	var toolbar: Control = _main.get_node("UI/Toolbar") as Control
	var slot: Control = toolbar.get_node("Slots/StonePickaxe") as Control
	_check(slot.modulate == Color.WHITE, "fifth slot highlights")
	var centered: float = (_main.get_viewport_rect().size.x - toolbar.size.x) * 0.5
	_check(is_equal_approx(toolbar.position.x, centered), "five-slot toolbar centered")
	_player._select_tool(5)
	_check(_player.current_tool == &"hoe", "tools cycle from pickaxe to hoe")
	_player._select_tool(-1)
	_check(_player.current_tool == &"stone_pickaxe", "previous tool wraps to pickaxe")


func _new_rock(cell: Vector2i, label: String) -> Sprite2D:
	var rock: Sprite2D = ROCK.instantiate() as Sprite2D
	rock.name = label
	rock.position = _tiller._soil.map_to_local(cell) + Vector2(0, 4)
	_world.add_child(rock)
	return rock


func _place(cell: Vector2i, facing: StringName) -> void:
	var direction: Vector2i = Vector2i.DOWN
	match facing:
		&"up": direction = Vector2i.UP
		&"left": direction = Vector2i.LEFT
		&"right": direction = Vector2i.RIGHT
	_player.global_position = _tiller._soil.to_global(_tiller._soil.map_to_local(cell - direction)) + Vector2(0, 1)
	_player.velocity = Vector2.ZERO
	_player._facing = facing
	_player._select_tool(4)


func _check_four_directions() -> void:
	var cell: Vector2i = Vector2i(17, 14)
	for facing: StringName in DIRECTIONS:
		var rock: Sprite2D = _new_rock(cell, "Direction_" + facing)
		_place(cell, facing)
		await physics_frame
		await physics_frame
		_check(_tiller.can_use(&"stone_pickaxe", cell), "reachable from " + facing)
		_check(not _tiller.can_use(&"axe", cell), "axe cannot mine")
		var stock: int = _inventory.count_of(&"stone")
		var before: int = _impacts
		var feet: Vector2 = _player.global_position
		_player._start_action()
		_check(_player.is_acting, "pickaxe action starts: " + facing)
		_check(rock.hits_remaining == 3, "no damage during ready")
		_player._start_action()
		_player._select_tool(0)
		Input.action_press(&"move_right")
		await create_timer(0.20).timeout
		Input.action_release(&"move_right")
		_check(_player.global_position == feet, "movement locked during windup")
		_check(_player.current_tool == &"stone_pickaxe", "tool locked during windup")
		_check(rock.hits_remaining == 3, "raised pickaxe has not struck yet")
		await create_timer(0.15).timeout
		_check(rock.hits_remaining == 2 and _impacts == before + 1, "single strike after anticipation")
		_check(_impact_frame == 3 and _impact_cell == cell, "damage on fourth frame and locked cell")
		_check(_inventory.count_of(&"stone") == stock, "unbroken rock does not drop items")
		await create_timer(0.30).timeout
		_check(not _player.is_acting and _sprite.animation == StringName("idle_%s" % facing), "recovery puts away pickaxe and restores directional idle")
		for hit: int in 2:
			_player._start_action()
			await create_timer(0.65).timeout
		_check(not is_instance_valid(rock), "rock removed after third strike")
		_check(_inventory.count_of(&"stone") == stock + 3, "exactly three stone materials")
		_check(not _tiller._has_body(cell), "broken rock collision removed")
		var stamina_now := get_first_node_in_group(&"stamina") as Node
		if stamina_now != null:
			stamina_now.set(&"value", 1_000_000)
		_check(_tiller.can_use(&"hoe", cell), "cleared grass can be tilled")
		before = _impacts
		_player._start_action()
		_check(not _player.is_acting and _impacts == before, "empty target rejects mining")


func _check_full_bag() -> void:
	var saved: Dictionary = _inventory.to_dict()
	var cell: Vector2i = Vector2i(17, 14)
	var rock: Sprite2D = _new_rock(cell, "FullBagRock")
	rock.mine(Vector2i.DOWN)
	rock.mine(Vector2i.DOWN)
	for index: int in _inventory.slot_count():
		_inventory._slots[index] = {&"id": &"stone", &"count": 99}
	_inventory._slots[0][&"count"] = 98
	_place(cell, &"down")
	_check(not _inventory.has_space_for(&"stone", 3), "partial capacity does not fit full drop")
	_check(not _tiller.can_use(&"stone_pickaxe", cell), "last strike blocked when bag lacks space")
	_check(_tiller.interaction_hint(&"stone_pickaxe").contains("背包"), "full bag hint visible")
	var stock: int = _inventory.count_of(&"stone")
	_check(not rock.mine(Vector2i.DOWN), "impact-time capacity check rejects final strike")
	_check(rock.hits_remaining == 1 and not rock.is_broken, "full bag preserves rock and last hit")
	_check(_inventory.count_of(&"stone") == stock, "no partial award on blocked strike")
	_inventory.remove_item(&"stone", 2)
	_check(_tiller.can_use(&"stone_pickaxe", cell), "free space re-enables final strike")
	stock = _inventory.count_of(&"stone")
	_player._start_action()
	await create_timer(0.65).timeout
	_check(not is_instance_valid(rock) and _inventory.count_of(&"stone") == stock + 3, "full reward after making space")
	_inventory.from_dict(saved)


func _check_target_lock() -> void:
	var cell: Vector2i = Vector2i(17, 14)
	var rock: Sprite2D = _new_rock(cell, "LockedRock")
	_place(cell, &"down")
	_player.set_input_locked(true)
	_player._start_action()
	_check(not _player.is_acting, "open panel blocks action entry")
	_player.set_input_locked(false)
	_player._start_action()
	rock.queue_free()
	await process_frame
	var replacement: Sprite2D = _new_rock(cell, "ReplacementRock")
	await create_timer(0.65).timeout
	_check(replacement.hits_remaining == 3, "lost target never retargets a replacement")
	_check(not _player.is_acting, "lost target still completes recovery")
	replacement.queue_free()
	await process_frame


func _check_real_rock_and_save() -> void:
	var rock: Sprite2D = _world.get_node("Rock5") as Sprite2D
	var cell: Vector2i = Vector2i(16, 9)
	_place(cell, &"down")
	_check(_tiller.can_use(&"stone_pickaxe", cell), "existing map rock is mineable")
	rock.mine(Vector2i.DOWN)
	var saved: Dictionary = _tiller.to_dict()
	_check(int(saved[&"rocks"]["Rock5"]) == 2, "rock damage included in farm save")
	var restored: Sprite2D = _new_rock(Vector2i(17, 14), "RestoredRock")
	restored.restore_state(2)
	_check(restored.hits_remaining == 2, "partial damage restored")
	var stock: int = _inventory.count_of(&"stone")
	restored.restore_state(0)
	await process_frame
	_check(not is_instance_valid(restored) and _inventory.count_of(&"stone") == stock, "load of broken rock does not award drops")
	for hit: int in 2:
		_player._start_action()
		await create_timer(0.65).timeout
	_check(not is_instance_valid(rock), "real cached map rock safely deleted")
	_check(_tiller.can_use(&"hoe", cell), "real map rock no longer blocks farming")
	var states: Dictionary = _tiller.to_dict()[&"rocks"]
	_check(int(states["Rock5"]) == 0, "removed map rock stays recorded")
	var fresh: Node2D = MAIN.instantiate() as Node2D
	fresh.get_node("Systems/Save").autoload_enabled = false
	root.add_child(fresh)
	fresh.get_node("Systems/Time").running = false
	var fresh_tiller: Node2D = fresh.get_node("Farm/Tiller") as Node2D
	fresh_tiller.from_dict({"rocks": {"Rock5": 0, "Rock21": 2}})
	await process_frame
	_check(not fresh.get_node("Farm/World").has_node("Rock5"), "cleared rock absent in reloaded map")
	_check(fresh.get_node("Farm/World/Rock21").hits_remaining == 2, "other rock damage restored on fresh map")
	fresh.queue_free()
	await process_frame


func _on_impact(tool: StringName, cell: Vector2i) -> void:
	if tool == &"stone_pickaxe":
		_impacts += 1
		_impact_frame = _sprite.frame
		_impact_cell = cell
