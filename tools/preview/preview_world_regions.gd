extends SceneTree
## 真实渲染六张地图、地图总览和资源标注页。请勿使用 --headless。

const Layout = preload("res://scripts/world/maps/region_layout.gd")
const Catalog = preload("res://tools/lib/world_region_catalog.gd")
const OUTPUT: String = "res://art/previews/world_regions_v1/"
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(640, 360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	RenderingServer.set_default_clear_color(Color("34453b"))
	var overview := Image.create_empty(1920, 720, false, Image.FORMAT_RGBA8)
	for index: int in Layout.REGION_IDS.size():
		var id: String = Layout.REGION_IDS[index]
		var scene: Node2D = load("res://scenes/maps/" + id + "_preview.tscn").instantiate() as Node2D
		root.add_child(scene)
		current_scene = scene
		for frame: int in 8: await process_frame
		await RenderingServer.frame_post_draw
		var capture: Image = root.get_texture().get_image()
		_save(capture, id + ".png")
		capture.resize(640, 360, Image.INTERPOLATE_NEAREST)
		overview.blit_rect(capture, Rect2i(0, 0, 640, 360), Vector2i(index % 3, index / 3) * Vector2i(640, 360))
		scene.queue_free()
		await process_frame
		await process_frame
	_save(overview, "world_regions_overview.png")
	await _resources()
	print("[region_preview] %d errors; %s" % [_failures, ProjectSettings.globalize_path(OUTPUT)])
	quit(0 if _failures == 0 else 1)


func _resources() -> void:
	root.content_scale_size = Vector2i(640, 400)
	root.size = Vector2i(1280, 800)
	var page := Control.new()
	root.add_child(page)
	var title := Label.new()
	title.text = "地面资源与树木  ·  28类原创像素素材"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("eadbb6"))
	page.add_child(title)
	for index: int in Catalog.RESOURCES.size():
		var data: Resource = load("res://data/ground_resources/" + String(Catalog.RESOURCES[index][0]) + ".tres")
		var corner := Vector2(12 + (index % 7) * 89, 40 + (index / 7) * 88)
		var background := ColorRect.new()
		background.position = corner
		background.size = Vector2(84, 80)
		background.color = Color("56644b")
		page.add_child(background)
		var sprite := TextureRect.new()
		sprite.texture = data.texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = corner + Vector2(10, 2)
		sprite.size = Vector2(64, 58)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		page.add_child(sprite)
		var label := Label.new()
		label.text = data.display_name
		label.position = corner + Vector2(2, 62)
		label.size.x = 80
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color("f0dfb5"))
		page.add_child(label)
	for frame: int in 6: await process_frame
	await RenderingServer.frame_post_draw
	_save(root.get_texture().get_image(), "resources_contact.png")
	page.queue_free()
	await process_frame


func _save(image: Image, name: String) -> void:
	if image.save_png(OUTPUT + name) != OK: _failures += 1
