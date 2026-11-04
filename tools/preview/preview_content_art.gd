extends SceneTree
## 直接以 Godot 渲染库中成品，不读取或绘制外部游戏素材。
## godot --path . --script res://tools/preview/preview_content_art.gd

const ROOT: String = "res://assets/packs/content_v1/"
const OUTPUT: String = "res://art/previews/content_v1/"
var _viewport: SubViewport
var _stage: Node2D
var _font: SystemFont


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var sheets: Array = catalog.get("sheets", [])
	if sheets.is_empty():
		push_error("[content_preview] No prepared sheets")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var ignore: FileAccess = FileAccess.open(OUTPUT + ".gdignore", FileAccess.WRITE)
	ignore.store_string("")
	ignore.close()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Arial"])
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	for page: int in ceili(sheets.size() / 12.0):
		_reset(Vector2i(1440, 1040))
		_label("PIXEL FARM · 原创全品类素材", Vector2(24, 14), 28)
		_label("已整理 %d / %d 图集 · %d 张切片 · 第 %d 页" % [catalog["completed_sheet_count"], catalog["planned_sheet_count"], catalog["item_count"], page + 1], Vector2(24, 54), 16)
		for index: int in range(page * 12, mini(sheets.size(), (page + 1) * 12)):
			var local: int = index - page * 12
			var sheet: Dictionary = sheets[index]
			var position: Vector2 = Vector2(24 + (local % 4) * 354, 92 + (local / 4) * 306)
			_card(sheet, position, Vector2(338, 288))
		await _capture("overview_%02d.png" % (page + 1))
	for sheet: Dictionary in sheets:
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(str(sheet["path"])))
		var size: Vector2i = image.get_size()
		var factor: int = mini(3, maxi(1, 1400 / maxi(size.x, size.y)))
		_reset(Vector2i(maxi(640, size.x * factor + 48), maxi(360, size.y * factor + 120)))
		_label("%s · %d 张" % [sheet["id"], sheet["count"]], Vector2(24, 16), 22)
		_label("%d×%d 格 · 原生 %d×%d · Nearest / 48 色" % [sheet["columns"], sheet["rows"], sheet["cell_size"][0], sheet["cell_size"][1]], Vector2(24, 52), 15)
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.centered = false
		sprite.position = Vector2(24, 96)
		sprite.scale = Vector2.ONE * factor
		_stage.add_child(sprite)
		await _capture(str(sheet["id"]) + ".png")
	print("[content_preview] %d sheet pages + %d overview pages saved to %s" % [sheets.size(), ceili(sheets.size() / 12.0), OUTPUT])
	_viewport.queue_free()
	await process_frame
	quit(0)


func _reset(size: Vector2i) -> void:
	if is_instance_valid(_stage):
		_stage.free()
	_viewport.size = size
	_stage = Node2D.new()
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport.add_child(_stage)
	var background: ColorRect = ColorRect.new()
	background.color = Color("dfe4bb")
	background.size = Vector2(size)
	_stage.add_child(background)


func _label(value: String, position: Vector2, font_size: int) -> void:
	var label: Label = Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("514c40"))
	_stage.add_child(label)


func _card(sheet: Dictionary, position: Vector2, size: Vector2) -> void:
	var panel: ColorRect = ColorRect.new()
	panel.color = Color("c8d3a5")
	panel.position = position
	panel.size = size
	_stage.add_child(panel)
	_label(str(sheet["id"]), position + Vector2(8, 4), 16)
	_label("%d 张 / %s" % [sheet["count"], sheet["category"]], position + Vector2(8, 26), 12)
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(str(sheet["path"])))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	var factor: float = minf((size.x - 16) / image.get_width(), (size.y - 64) / image.get_height())
	sprite.scale = Vector2.ONE * factor
	sprite.position = position + Vector2(size.x / 2, 58 + (size.y - 64) / 2)
	_stage.add_child(sprite)


func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = _viewport.get_texture().get_image().save_png(OUTPUT + name)
	if error != OK:
		push_error("[content_preview] Save failed: " + name)
