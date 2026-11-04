extends SceneTree
## 在真实农场并排查看浆果状态和旧作物；关闭自动读写存档。

const Bush = preload("res://scripts/world/resources/berry_bush.gd")
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_main = load("res://scenes/main.tscn").instantiate() as Node2D
	_main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Save").remove_from_group(&"save")
	_main.get_node("Systems/Time").running = false
	_main.get_node("Systems/Weather").lock(&"sunny")
	_main.get_node("Farm/Tiller").set_process(false)
	_main.get_node("Farm/Tiller").hide()
	await process_frame
	await process_frame
	for bush: Node in get_nodes_in_group(&"berry_bush"):
		(bush as CanvasItem).hide()
	for pickup: Node2D in _main.get_node("Systems/FarmActivities").pickups:
		pickup.hide()
	var world: Node2D = _main.get_node("Farm/World") as Node2D
	var kinds: Array[StringName] = [&"wild_blackberry", &"wild_raspberry", &"wild_gooseberry"]
	for column: int in 3:
		for row: int in 3:
			var bush: Node2D = Bush.new()
			bush.set("kind", kinds[column])
			bush.set("stage", 0 if row == 0 else 1)
			bush.set("regrow_day", 10 if row == 1 else 0)
			bush.position = Vector2(48 + column * 40, 208 + row * 40)
			world.add_child(bush)
	_main.get_node("Farm/World/Player").global_position = Vector2(112, 304)
	var camera: Node = _main.get_node("Camera")
	camera.set_view_zoom(1.8, true, false)
	camera._physics_process(1.0)
	camera.set_physics_process(false)
	camera.global_position = Vector2(180, 240)
	camera.reset_smoothing()
	for panel: Node in _main.get_node("UI").get_children():
		if panel is CanvasItem: panel.hide()
	_add_caption("野浆果像素贴图 · 黑莓 / 红莓 / 醋栗", "从上至下：幼苗 / 采摘后 / 成熟；右侧为现有地图素材")
	await _shot("wild-berries")
	var tiller: Node = _main.get_node("Farm/Tiller")
	for column: int in 4:
		var id: String = ["carrot", "tomato", "potato", "blueberry"][column]
		var data: CropData = load("res://data/crops/" + id + ".tres") as CropData
		var cell: Vector2i = Vector2i(18 + column * 2, 7)
		tiller._soil_state[cell] = false
		tiller._refresh_cell(cell)
		tiller._spawn_crop(cell, data, data.last_stage(), false)
	_main.get_node("Farm/World/Player").global_position = Vector2(344, 159)
	camera.set_view_zoom(2.0, true, false)
	camera._physics_process(1.0)
	camera.reset_smoothing()
	_main.get_node("UI/StyleCaption/Title").text = "作物对照 · 胡萝卜 / 番茄 / 土豆 / 蓝莓"
	_main.get_node("UI/StyleCaption/Detail").text = "原有作物与重制素材同场景、同镜头显示"
	await _shot("crops")
	_main.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	for audio: Node in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer: audio.stream = null
	await create_timer(0.1).timeout
	quit()


func _add_caption(title: String, detail: String) -> void:
	var frame: Panel = Panel.new()
	frame.name = "StyleCaption"
	frame.position = Vector2(8, 8)
	frame.size = Vector2(624, 46)
	var skin: StyleBoxFlat = StyleBoxFlat.new()
	skin.bg_color = Color("eee3c2")
	skin.border_color = Color("8e6b4c")
	skin.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", skin)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	for index: int in 2:
		var label: Label = Label.new()
		label.name = "Title" if index == 0 else "Detail"
		label.text = title if index == 0 else detail
		label.position = Vector2(8, 5 + index * 20)
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 10 if index == 0 else 7)
		label.add_theme_color_override("font_color", Color("514c40"))
		frame.add_child(label)
	_main.get_node("UI").add_child(frame)


func _shot(name: String) -> void:
	for frame: int in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var directory: String = "res://build/farm-previews"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory + "/style-v2-" + name + ".png")
	print("[farm_style] " + directory + "/style-v2-" + name + ".png")
