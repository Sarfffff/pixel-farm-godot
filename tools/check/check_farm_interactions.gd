extends SceneTree
## 真实场景回归：目标锁定、动画命中时序、障碍、浇水与倒树碰撞。
## --headless --path . --script res://tools/check/check_farm_interactions.gd
## 加 -- --preview 可在有窗口模式输出截图到 user://farm_previews/。

var _main: Node2D
var _player: CharacterBody2D
var _tiller: Node2D
var _sprite: AnimatedSprite2D
var _inventory: Inventory
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
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	# 关掉自动读档：测试固定从干净的开局状态出发，不受真实存档影响
	_main.get_node("Systems/Save").autoload_enabled = false
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	_tiller = _main.get_node("Farm/Tiller") as Node2D
	_sprite = _player.get_node("Sprite") as AnimatedSprite2D
	_inventory = _main.get_node("Systems/Inventory") as Inventory
	# 体力系统会限制连续干活：这套长序列回归只验证动画/命中/障碍，
	# 给它足够的体力，避免中途被"体力不足"挡住而产生假失败。
	var stamina := get_first_node_in_group(&"stamina") as Node
	if stamina != null:
		stamina.set(&"value", 1_000_000)
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

	# 防回归：遮住格子的 NPC 不该把地锁死（曾经把走动的 NPC 当成树冠，整格不可锄）。
	var gardener := _main.get_node_or_null("Farm/World/Gardener") as Sprite2D
	if gardener != null:
		gardener.set(&"stationary", true)
		gardener.global_position = _tiller._soil.to_global(_tiller._soil.map_to_local(Vector2i(17, 14)))
		await physics_frame
		await physics_frame
		_check(_tiller.can_use(&"hoe", Vector2i(17, 14)), "a standing NPC does not block tilling")
		gardener.global_position = Vector2(400, 60)
	_check(not _tiller.can_use(&"hoe", Vector2i(29, 8)), "cottage blocks tilling")
	_check(not _tiller.can_use(&"hoe", Vector2i(18, 6)), "existing soil cannot be tilled twice")
	_check(_tiller._block_reason(Vector2i(29, 11)) == &"ground", "planked path reports ground block")
	_check(not _tiller.can_use(&"hoe", Vector2i(29, 11)), "planked path cannot be tilled")
	_check(not _tiller.can_use(&"watering_can", Vector2i(16, 5)), "empty ground cannot be watered")

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
	_check(_sprite.animation == &"idle_down", "hoe put away after recovery")

	# 空耕地不能浇水：先种下作物，水壶才有作用对象
	var crop_cell := Vector2i(16, 5)
	_check(not _tiller.can_use(&"watering_can", crop_cell), "empty tilled soil cannot be watered")
	_tiller._on_use_requested(&"seeds", crop_cell)
	_check(_tiller._crops.has(crop_cell), "crop planted for the watering test")
	_player._select_tool(1)
	_player._start_action()
	_check(not _tiller._soil_state[crop_cell], "dry during watering windup")
	await create_timer(0.18).timeout
	_check(_tiller._soil_state[crop_cell], "watering impact updates soil")
	await _capture("02-water")
	await create_timer(0.45).timeout
	var before: int = _impacts
	_player._start_action()
	_check(not _player.is_acting and _impacts == before, "wet tile rejects repeat watering")

	# 种子袋：在另一条空耕地上验证播种动画与命中帧
	var seed_cell := Vector2i(17, 5)
	_tiller._on_use_requested(&"hoe", seed_cell)
	_check(_tiller._soil_state.has(seed_cell), "second plot tilled for seeding")
	_place(seed_cell, &"down")
	_player._select_tool(2)
	_check(not _tiller._crops.has(seed_cell), "cell is empty before seeding")
	_player._start_action()
	_check(_player.is_acting, "seeds start the planting animation")
	await create_timer(0.22).timeout
	_check(_tiller._crops.has(seed_cell), "seed plants at strike frame")
	await _capture("05-seeds-help")
	await create_timer(0.45).timeout
	_check(not _player.is_acting, "recovery unlocks after planting")

	# 所有工具、四个方向的动画都实际播放到命中和收手。
	for tool_index: int in [0, 1, 3]:
		for facing: StringName in [&"down", &"up", &"left", &"right"]:
			var cell := Vector2i(17, 14)
			var tree: Sprite2D
			if tool_index == 3:
				tree = load("res://scenes/world/props/tree_small.tscn").instantiate() as Sprite2D
				tree.position = Vector2(cell) * 16 + Vector2(8, 11)
				_main.get_node("Farm/World").add_child(tree)
				_check(_tiller._block_reason(cell + Vector2i.UP) == &"prop", "tree canopy blocks tilling above trunk")
				_check(not _tiller.can_use(&"hoe", cell + Vector2i.UP), "canopy cell cannot be tilled")
			else:
				_tiller._soil_state.erase(cell)
				if tool_index == 1:
					# 水壶只作用于作物：保证目标格上有一株未浇水的苗
					_tiller._soil_state[cell] = false
					if _tiller._crops.has(cell):
						var crop: Crop = _tiller._crops[cell]
						crop.begin_day()
						crop.stage = 0
						crop.apply_stage()
					else:
						_tiller._on_use_requested(&"seeds", cell)
			_place(cell, facing)
			_player._select_tool(tool_index)
			await physics_frame
			await physics_frame
			# 每一轮都补满体力：这套长序列只验证动画与命中，不该被体力拦住。
			var stamina_now := get_first_node_in_group(&"stamina") as Node
			if stamina_now != null:
				stamina_now.set(&"value", 1_000_000)
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
				var wood_before: int = _inventory.count_of(&"wood")
				_player._start_action()
				await create_timer(0.65).timeout
				_check(tree.is_felled, "tree falls after required hits")
				_check(tree.get_node("Body").collision_layer == 1, "stump retains collision")
				_check(_inventory.count_of(&"wood") == wood_before + 2, "small tree drops 2 wood into bag")
				_check(_tiller._tree_at(cell) == null, "fallen tree no longer a trunk target")
				_check(_tiller._stump_at(cell) == tree, "stump becomes the axe target")
				_check(not _tiller.can_use(&"hoe", cell), "stump blocks tilling")
				_check_stump_from_four_sides(tree)
				# 树桩还能再用斧头清一次：掉 1 根木材、碰撞移除、脚下可开垦
				_place(cell, &"up")
				_player._select_tool(3)
				var wood_before_stump: int = _inventory.count_of(&"wood")
				_player._start_action()
				_check(_player.is_acting, "axe starts on the stump")
				await create_timer(0.55).timeout
				_check(_inventory.count_of(&"wood") == wood_before_stump + 1, "clearing stump drops 1 wood")
				_check(_tiller._stump_at(cell) == null, "stump cleared away")
				_check(not _tiller._has_body(cell), "cleared stump no longer blocks the cell")
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
		var wood_before: int = _inventory.count_of(&"wood")
		for hit in 3:
			_player._start_action()
			await create_timer(0.65).timeout
		_check(real_tree.is_felled, "real map tree felled")
		_check(_inventory.count_of(&"wood") == wood_before + 3, "big tree drops 3 wood into bag")
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

	# 身边一圈：面前那格已经开垦时，自动改选旁边的空地并把角色转过去
	_place(Vector2i(21, 6), &"down")
	_check(_tiller.target_cell() == Vector2i(21, 6), "front cell is the plot row")
	_check(not _tiller.can_use(&"hoe", Vector2i(21, 6)), "front cell already tilled")
	var side_cell: Vector2i = _tiller.resolve_target(&"hoe")
	_check(side_cell == Vector2i(22, 6), "neighbor cell picked when front is unusable")
	_player._select_tool(0)
	_player._start_action()
	_check(_player.facing_vector() == Vector2i.RIGHT, "player turns toward the neighbor cell")
	await create_timer(0.22).timeout
	_check(_tiller._soil_state.has(Vector2i(22, 6)), "neighbor cell tilled after the strike")
	await create_timer(0.45).timeout

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
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


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
