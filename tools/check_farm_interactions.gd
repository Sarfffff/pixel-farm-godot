extends SceneTree
## 真实场景回归：目标锁定、动画命中时序、障碍、浇水与倒树碰撞。
## --headless --path . --script res://tools/check_farm_interactions.gd
## 加 -- --preview 可在有窗口模式输出截图到 user://farm_previews/。

var _main: Node2D
var _player: CharacterBody2D
var _tiller: Node2D
var _sprite: AnimatedSprite2D
var _failures: int = 0
var _impacts: int = 0
var _preview: bool = false


func _init() -> void:
	_preview = OS.get_cmdline_user_args().has("--preview")
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[farm_interactions] FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	_tiller = _main.get_node("Farm/Tiller") as Node2D
	_sprite = _player.get_node("Sprite") as AnimatedSprite2D
	_player.use_requested.connect(_on_impact)
	await physics_frame
	await physics_frame
	# 等待首次 TileMap 碰撞/渲染更新，避免加载首帧占用动作计时。
	await create_timer(0.25).timeout
	_check(_player.interaction == _tiller, "player connected to tiller")
	_check(_tiller._soil_state.size() == 48, "initial plots")
	var soil_image: Image = _tiller._soil.tile_set.get_source(0).texture.get_image()
	_check(soil_image.get_pixel(2, 1).a > 0.9, "single soil tile has square shoulders instead of circle")
	_check(soil_image.get_pixel(0, 0).a == 0.0, "single soil tile retains tiny pixel cut corner")
	_check(_tiller.can_use(&"hoe", Vector2i(16, 5)), "independent new plot allowed")
	_check(not _tiller.can_use(&"hoe", Vector2i(15, 5)), "outside farming area blocked")
	_check(not _tiller.can_use(&"hoe", Vector2i(16, 9)), "rock blocks tilling")
	_check(not _tiller.can_use(&"hoe", Vector2i(29, 8)), "cottage blocks tilling")
	_check(not _tiller.can_use(&"hoe", Vector2i(18, 6)), "existing soil cannot be tilled twice")
	_check(not _tiller.can_use(&"watering_can", Vector2i(16, 5)), "grass cannot be watered")

	# 一次真实动画：起手不改地，移动/切工具/连点不能改目标或重复提交。
	_place(Vector2i(16, 5), &"down")
	_player._select_tool(0)
	var feet: Vector2 = _player.global_position
	_player._start_action()
	_check(_player.is_acting, "action starts")
	_check(not _tiller._soil_state.has(Vector2i(16, 5)), "no soil before impact")
	_player._select_tool(1)
	_player._start_action()
	Input.action_press(&"move_right")
	await create_timer(0.10).timeout
	_check(_player.global_position == feet, "movement locked during action")
	_check(_player.current_tool == &"hoe", "tool locked during action")
	_check(not _tiller._soil_state.has(Vector2i(16, 5)), "windup has no effect")
	Input.action_release(&"move_right")
	await create_timer(0.10).timeout
	_check(_tiller._soil_state.has(Vector2i(16, 5)), "soil created at strike frame")
	_check(_impacts == 1, "one impact despite duplicate input")
	await _capture("01-hoe")
	await create_timer(0.35).timeout
	_check(not _player.is_acting, "recovery unlocks player")
	_check(_sprite.animation == &"idle_down", "idle restored")

	_player._select_tool(1)
	_player._start_action()
	_check(not _tiller._soil_state[Vector2i(16, 5)], "dry during watering windup")
	await create_timer(0.18).timeout
	_check(_tiller._soil_state[Vector2i(16, 5)], "watering impact updates soil")
	await _capture("02-water")
	await create_timer(0.45).timeout
	var before: int = _impacts
	_player._start_action()
	_check(not _player.is_acting and _impacts == before, "wet tile rejects repeat watering")
	_player._select_tool(2)
	_player._start_action()
	_check(not _player.is_acting, "unimplemented seeds do not play phantom hoe animation")
	await physics_frame
	await _capture("05-seeds-help")

	# 所有工具、四个方向的动画都实际播放到命中和收手。
	for tool_index: int in [0, 1, 3]:
		for facing: StringName in [&"down", &"up", &"left", &"right"]:
			var cell := Vector2i(17, 14)
			var tree: Sprite2D
			if tool_index == 3:
				tree = load("res://scenes/world/props/tree_small.tscn").instantiate() as Sprite2D
				tree.position = Vector2(cell) * 16 + Vector2(8, 11)
				_main.get_node("Farm/World").add_child(tree)
			else:
				_tiller._soil_state.erase(cell)
				if tool_index == 1:
					_tiller._soil_state[cell] = false
			_place(cell, facing)
			_player._select_tool(tool_index)
			await physics_frame
			await physics_frame
			before = _impacts
			_player._start_action()
			_check(_player.is_acting, "starts %s/%s" % [_player.current_tool, facing])
			await create_timer(0.22).timeout
			_check(_impacts == before + 1, "single strike %s/%s" % [_player.current_tool, facing])
			if tool_index == 3:
				_check(tree.hits_remaining == 1, "axe damages tree once")
			await _capture("%s-%s" % [_player.current_tool, facing])
			await create_timer(0.40).timeout
			_check(not _player.is_acting, "finishes %s/%s" % [_player.current_tool, facing])
			if tree != null:
				_player._start_action()
				await create_timer(0.65).timeout
				_check(tree.is_felled, "tree falls after required hits")
				_check(tree.get_node("Body").collision_layer == 1, "stump retains collision")
				_check(_tiller._tree_at(cell) == null, "stump no longer axe target")
				_check(not _tiller.can_use(&"hoe", cell), "stump blocks tilling")
				_check_stump_from_four_sides(tree)
				tree.queue_free()
				await process_frame

	# 真实地图中被遮挡系统缓存的树：倒下后不应继续按旧树冠范围淡出。
	var real_tree: Sprite2D
	for candidate: Node in get_nodes_in_group(&"choppable"):
		if candidate.position == Vector2(296, 72):
			real_tree = candidate as Sprite2D
	_check(real_tree != null, "real map tree exists")
	if real_tree != null:
		_place(Vector2i(18, 4), &"up")
		_player._select_tool(3)
		for hit in 3:
			_player._start_action()
			await create_timer(0.65).timeout
		_check(real_tree.is_felled, "real map tree felled")
		_check(real_tree.get_meta(&"felled", false), "stump excluded from old occlusion bounds")
		_check(real_tree.get_node("Body").collision_layer == 1, "real stump still blocks walking")
		_check_stump_from_four_sides(real_tree)
		_player.global_position = real_tree.global_position + Vector2(0, 21)
		_player.velocity = Vector2.ZERO
		Input.action_press(&"move_up")
		for tick in 30:
			await physics_frame
		Input.action_release(&"move_up")
		_check(_player.global_position.y >= real_tree.global_position.y + 8.0, "actual walking cannot enter stump")
		_player.velocity = Vector2.ZERO
		_place(Vector2i(18, 4), &"up")
		await _capture("04-felled-tree")

	# 凹角 / 窄条 / 独立格 / 湿土交界，供截图检查连边。
	for cell: Vector2i in [Vector2i(20, 5), Vector2i(21, 5), Vector2i(22, 5), Vector2i(22, 6), Vector2i(22, 7)]:
		_tiller._soil_state[cell] = false
		_tiller._refresh_region(cell)
	for cell: Vector2i in [Vector2i(18, 10), Vector2i(19, 10), Vector2i(18, 11)]:
		_tiller._soil_state[cell] = true
		_tiller._refresh_cell(cell)
	_player.global_position = Vector2(352, 148)
	await create_timer(0.65).timeout
	await _capture("03-soil-overview")
	print("[farm_interactions] %s (%d failures, %d impacts)" % ["PASS" if _failures == 0 else "FAIL", _failures, _impacts])
	_main.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _place(cell: Vector2i, facing: StringName) -> void:
	_player._facing = facing
	_player.global_position = Vector2(cell - _player.facing_vector()) * 16 + Vector2(8, 9)
	_player.velocity = Vector2.ZERO


func _on_impact(_tool: StringName, _cell: Vector2i) -> void:
	_impacts += 1
	_check(_sprite.frame == (1 if _tool == &"watering_can" else 2), "impact matches correct tool frame")


func _check_stump_from_four_sides(tree: Sprite2D) -> void:
	for direction: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		_player.global_position = tree.global_position + Vector2(direction) * 20 + Vector2(0, 1)
		var collision := KinematicCollision2D.new()
		var blocked: bool = _player.test_move(_player.global_transform, -Vector2(direction) * 30, collision)
		_check(blocked and collision.get_collider() == tree.get_node("Body"), "stump blocks approach from %s" % direction)


func _capture(label: String) -> void:
	if not _preview:
		return
	await RenderingServer.frame_post_draw
	var directory: String = OS.get_user_data_dir().path_join("farm_previews")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print("[preview] " + directory.path_join(label + ".png"))
