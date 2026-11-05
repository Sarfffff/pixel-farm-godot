extends SceneTree
## 隔离于玩家保存的真实渲染；只改变内存镜头，展示两座桥、道路和旧档纠偏。

const OUTPUT: String = "res://build/terrain-v2/"
var _main: Node2D
var _camera: Camera2D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Save").remove_from_group(&"save")
	_main.get_node("Systems/Time").running = false
	_main.get_node("Systems/Weather").lock(&"sunny")
	_main.get_node("UI").hide()
	_camera = _main.get_node("Camera") as Camera2D
	_camera.set_physics_process(false)
	for frame: int in 8:
		await process_frame
	for actor: Node in get_nodes_in_group(&"world_actor"):
		if actor is CanvasItem:
			(actor as CanvasItem).hide()
	_main.get_node("Farm/World/Player").hide()
	await _capture("horizontal-bridge", Vector2(208, 256), 3.0)
	await _capture("vertical-bridge", Vector2(352, 376), 3.0)
	await _capture("path", Vector2(376, 256), 4.0)
	await _capture("farm", Vector2(320, 240), 1.0)
	# 模拟用户已有存档的桥上/河上灌木，不接触任何磁盘槽位。
	var grove: Node = _main.get_node("Farm/World/BerryGrove")
	var data: Dictionary = grove.to_dict()
	var rows: Array = data.bushes
	if rows.size() >= 2:
		rows[0].x = 208
		rows[0].y = 256
		rows[1].x = 352
		rows[1].y = 380
	grove.from_dict(data)
	await _capture("legacy-save-repaired", Vector2(208, 256), 2.0)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0)


func _capture(label: String, point: Vector2, zoom_value: float) -> void:
	_camera.zoom = Vector2(zoom_value, zoom_value)
	_camera.global_position = point
	_camera.reset_smoothing()
	_camera.force_update_scroll()
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(OUTPUT + label + ".png")
	assert(error == OK, "terrain capture failed")
	print("[terrain_art_preview] " + label)
