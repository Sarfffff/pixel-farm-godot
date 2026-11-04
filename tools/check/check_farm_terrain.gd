extends SceneTree
## 实际物理世界验收：水格/桥格碰撞一致、两桥双向通行、护栏、坡地与全图可达性。
## --headless --path . --script res://tools/check/check_farm_terrain.gd
## 有窗口运行并加 -- --preview，另输出全图与实机截图到 user://terrain_previews/。

const Landscape := preload("res://tools/lib/farm_landscape.gd")
var _main: Node2D
var _player: CharacterBody2D
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[farm_terrain] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	# 关掉自动读档：测试固定从干净的开局状态出发，不受真实存档影响
	_main.get_node("Systems/Save").autoload_enabled = false
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	await physics_frame
	await physics_frame
	await create_timer(0.2).timeout
	var farm: Node2D = _main.get_node("Farm") as Node2D
	var water: TileMapLayer = farm.get_node("Water") as TileMapLayer
	var collision: TileMapLayer = farm.get_node("WaterCollision") as TileMapLayer
	var cells: Dictionary[Vector2i, bool] = Landscape.water_cells()
	for cell: Vector2i in cells:
		var bridge: bool = Landscape.on_bridge(cell)
		_check(water.get_cell_source_id(cell) == 2, "water drawn at %s" % cell)
		_check((collision.get_cell_source_id(cell) == -1) == bridge, "collision/deck agree at %s" % cell)
		_check(_solid(Vector2(cell * 16 + Vector2i(8, 8))) != bridge, "real physics at %s" % cell)
	var source: TileSetAtlasSource = water.tile_set.get_source(2) as TileSetAtlasSource
	_check(source.get_tile_animation_frames_count(Vector2i.ZERO) == 4, "four-frame native water animation")
	_check(not _solid(Vector2(472, 176)), "spawn remains clear")
	_check(_solid(Vector2(72, 120)), "raised bluff blocks walking")
	for child: Node in farm.get_node("World").get_children():
		if not child is Node2D:
			continue
		var prop := child as Node2D
		if prop == _player:
			continue
		# 浮标、钓线这类水面视觉物本就该在水里，不参与"脚下要干燥"的检查。
		if prop.is_in_group(&"water_visual"):
			continue
		var cell: Vector2i = Vector2i((prop.position - Vector2(0, 1)) / 16)
		_check(not cells.has(cell), "prop has dry feet: %s" % prop.name)
	# 以实际玩家碰撞形状横穿两桥，分别测试两方向，且不能从桥侧下水。
	_clear_move(Vector2(136, 257), Vector2(144, 0), "west to east bridge")
	_clear_move(Vector2(280, 257), Vector2(-144, 0), "east to west bridge")
	_clear_move(Vector2(352, 310), Vector2(0, 148), "north to south bridge")
	_clear_move(Vector2(352, 458), Vector2(0, -148), "south to north bridge")
	_blocked_move(Vector2(208, 257), Vector2(0, -24), "horizontal bridge north rail")
	_blocked_move(Vector2(208, 257), Vector2(0, 24), "horizontal bridge south rail")
	_blocked_move(Vector2(352, 380), Vector2(-24, 0), "vertical bridge west rail")
	_blocked_move(Vector2(352, 380), Vector2(24, 0), "vertical bridge east rail")
	_check_reachability()
	if OS.get_cmdline_user_args().has("--preview"):
		await _previews()
	print("[farm_terrain] %s (%d failures; %d water cells)" % ["PASS" if _failures == 0 else "FAIL", _failures, cells.size()])
	_main.queue_free()
	await process_frame
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _solid(point: Vector2) -> bool:
	var query: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	return not _player.get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


func _clear_move(start: Vector2, motion: Vector2, label: String) -> void:
	_player.position = start
	_check(not _player.test_move(_player.global_transform, motion), label)


func _blocked_move(start: Vector2, motion: Vector2, label: String) -> void:
	_player.position = start
	_check(_player.test_move(_player.global_transform, motion), label)


func _check_reachability() -> void:
	var reached: Dictionary[Vector2i, bool] = {Vector2i(29, 11): true}
	var pending: Array[Vector2i] = [Vector2i(29, 11)]
	var index: int = 0
	while index < pending.size():
		var cell: Vector2i = pending[index]
		index += 1
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if reached.has(next) or not Rect2i(0, 0, 40, 30).has_point(next):
				continue
			var point: Vector2 = Vector2(next * 16 + Vector2i(8, 9))
			if _solid(point - Vector2(0, 3)):
				continue
			_player.position = Vector2(cell * 16 + Vector2i(8, 9))
			if _player.test_move(_player.global_transform, Vector2(step * 16)):
				continue
			reached[next] = true
			pending.append(next)
	for target: Vector2i in [Vector2i(5, 16), Vector2i(21, 28), Vector2i(37, 28), Vector2i(18, 14), Vector2i(29, 18)]:
		_check(reached.has(target), "reachable from spawn: %s" % target)


func _previews() -> void:
	var camera: Camera2D = _main.get_node("Camera") as Camera2D
	camera.set_physics_process(false)
	_player.position = Vector2(472, 176)
	_main.get_node("UI").hide()
	root.size = Vector2i(1280, 960)
	root.content_scale_size = Vector2i(640, 480)
	camera.position = Vector2(320, 240)
	camera.reset_smoothing()
	await _capture("01-map-overview")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(320, 180)
	_main.get_node("UI").show()
	_player.position = Vector2(288, 256)
	camera.position = Vector2(288, 246)
	camera.reset_smoothing()
	await _capture("02-river-bridge")
	_player.position = Vector2(352, 306)
	camera.position = Vector2(432, 346)
	camera.reset_smoothing()
	await _capture("03-pond-crossing")
	_player.position = Vector2(128, 192)
	camera.position = Vector2(160, 150)
	camera.reset_smoothing()
	await _capture("04-bluff-bank")


func _capture(label: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var directory: String = OS.get_user_data_dir().path_join("terrain_previews")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print("[terrain_preview] " + directory.path_join(label + ".png"))
