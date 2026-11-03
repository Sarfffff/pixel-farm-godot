extends SceneTree

const PLAYER: PackedScene = preload("res://scenes/player/player.tscn")
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe", &"stone_pickaxe"]
const DIRECTIONS: Array[StringName] = [&"down", &"up", &"left", &"right"]
const VECTORS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
const MOVEMENT: Array[StringName] = [&"move_down", &"move_up", &"move_left", &"move_right"]

class InteractionStub extends Node:
	var cell: Vector2i = Vector2i.DOWN

	func can_use(_tool: StringName, _cell: Vector2i) -> bool:
		return true

	func resolve_target(_tool: StringName) -> Vector2i:
		return cell

	func base_cell() -> Vector2i:
		return Vector2i.ZERO

var _player: CharacterBody2D
var _sprite: AnimatedSprite2D
var _interaction: InteractionStub
var _failures: int = 0
var _impacts: int = 0
var _impact_frame: int = -1
var _impact_tool: StringName


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[held_tools] FAIL: " + message)


func _run() -> void:
	_player = PLAYER.instantiate() as CharacterBody2D
	root.add_child(_player)
	current_scene = _player
	_sprite = _player.get_node("Sprite") as AnimatedSprite2D
	_interaction = InteractionStub.new()
	root.add_child(_interaction)
	_player.interaction = _interaction
	_player.use_requested.connect(_on_impact)
	_check(_sprite.animation == &"idle_down" and _player.current_tool == &"hoe", "default tool is selected without a carry overlay")
	_check_assets()
	await _check_movement_and_switching()
	await _check_action_transitions()
	_check(_impacts == 20, "idle and walk never submit extra tool hits")
	_player.queue_free()
	_interaction.queue_free()
	await process_frame
	print("[held_tools] %s; %d failures" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _check_assets() -> void:
	var frames: SpriteFrames = _sprite.sprite_frames
	for direction: StringName in DIRECTIONS:
		for state: String in ["idle", "walk"]:
			var animation: StringName = StringName("%s_%s" % [state, direction])
			_check(frames.has_animation(animation), "natural animation exists: " + animation)
			if not frames.has_animation(animation):
				continue
			var count: int = 4 if state == "walk" else 1
			_check(frames.get_frame_count(animation) == count, "original step count preserved")
			_check(frames.get_animation_loop(animation) == (state == "walk"), "walk loops, idle does not")
			var steps: Dictionary[String, bool] = {}
			for phase: int in count:
				var atlas: AtlasTexture = frames.get_frame_texture(animation, phase) as AtlasTexture
				_check(atlas != null and atlas.atlas.resource_path == "res://assets/game/characters/basic_charakter_spritesheet.png", "natural movement uses original character artwork")
				if atlas == null:
					continue
				var image: Image = atlas.get_image()
				_check(image.get_size() == Vector2i(16, 16) and image.get_used_rect().size != Vector2i.ZERO, "original 16px body without equipment overlay")
				steps[image.get_data().hex_encode()] = true
				for y: int in 16:
					for x: int in 16:
						var alpha: float = image.get_pixel(x, y).a
						_check(alpha == 0.0 or alpha == 1.0, "binary character alpha")
			if state == "walk":
				_check(steps.size() == 4, "four distinct original walking steps")


func _check_movement_and_switching() -> void:
	for direction_index: int in 4:
		var facing: StringName = DIRECTIONS[direction_index]
		_player._facing = facing
		_player._update_animation(false)
		for tool_index: int in TOOLS.size():
			var tool: StringName = TOOLS[tool_index]
			var event: InputEventKey = InputEventKey.new()
			event.keycode = KEY_1 + tool_index
			event.physical_keycode = KEY_1 + tool_index
			event.pressed = true
			_player._unhandled_input(event)
			_check(_player.current_tool == tool, "number selects tool")
			_check(_sprite.animation == StringName("idle_%s" % facing), "tool selection keeps natural idle")
			Input.action_press(MOVEMENT[direction_index])
			await create_timer(0.10).timeout
			_check(_player.velocity.length() > 0.0, "selected tools do not block movement")
			_check(_sprite.animation == StringName("walk_%s" % facing), "all tools use natural walking")
			_sprite.set_frame_and_progress(2, 0.35)
			_player._select_tool(tool_index + 1)
			_check(_sprite.frame == 2 and is_equal_approx(_sprite.frame_progress, 0.35), "switch preserves walking phase")
			_check(_player.current_tool == TOOLS[(tool_index + 1) % 5] and _sprite.animation == StringName("walk_%s" % facing), "moving switch changes tool but not body pose")
			var next_facing: StringName = DIRECTIONS[(direction_index + 1) % 4]
			_player._facing = next_facing
			_player._update_animation(true)
			_check(_sprite.animation == StringName("walk_%s" % next_facing) and _sprite.frame == 2 and is_equal_approx(_sprite.frame_progress, 0.35), "turn preserves natural walking phase")
			_player._facing = facing
			_player._select_tool(tool_index)
			Input.action_release(MOVEMENT[direction_index])
			await create_timer(0.12).timeout
			_check(_sprite.animation == StringName("idle_%s" % facing), "stop restores natural idle")
			_player.set_input_locked(true)
			_check(_sprite.animation == StringName("idle_%s" % facing), "panel lock preserves natural idle")
			_player.set_input_locked(false)
	_check(_impacts == 0, "idle and walking never trigger mining or tilling")


func _check_action_transitions() -> void:
	for direction_index: int in 4:
		var facing: StringName = DIRECTIONS[direction_index]
		_player._facing = facing
		_interaction.cell = VECTORS[direction_index]
		for tool_index: int in TOOLS.size():
			var tool: StringName = TOOLS[tool_index]
			_player._select_tool(tool_index)
			_player._update_animation(false)
			var before: int = _impacts
			var position: Vector2 = _player.position
			_player._start_action()
			var action_tool: StringName = &"hoe" if tool == &"seeds" else tool
			_check(_player.is_acting and _sprite.animation == StringName("%s_%s" % [action_tool, facing]), "original use action remains separate")
			_player._select_tool(tool_index + 1)
			_check(_player.current_tool == tool, "use action prevents appearance switching")
			await create_timer(0.05).timeout
			_check(_impacts == before, "no impact at ready pose")
			await create_timer(0.70).timeout
			_check(not _player.is_acting, "use action finishes")
			_check(_sprite.animation == StringName("idle_%s" % facing) and _player.current_tool == tool, "recovery puts away tool without changing selection")
			_check(_player.position == position, "natural movement and action origins do not drift")
			var expected_frame: int = 3 if tool == &"stone_pickaxe" else (1 if tool == &"watering_can" else 2)
			_check(_impacts == before + 1 and _impact_tool == tool and _impact_frame == expected_frame, "original single-hit timing preserved")


func _on_impact(tool: StringName, _cell: Vector2i) -> void:
	_impacts += 1
	_impact_frame = _sprite.frame
	_impact_tool = tool
