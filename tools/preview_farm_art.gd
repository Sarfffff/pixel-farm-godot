extends SceneTree
## 在 Godot 中渲染素材验收页，不更改源图片。

var _font: SystemFont
var _canvas: Node2D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 768)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(_canvas)
	var background := ColorRect.new()
	background.size = Vector2(1024, 768)
	background.color = Color("c2cd87")
	_canvas.add_child(background)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	_label("像素农场 · 新增素材", Vector2(24, 14), 30)
	_label("32 张工具动作帧 · 24 张作物图 · 16 张物品图标 · 全部已存入项目", Vector2(24, 58), 18)
	_label("锄地：向下入土", Vector2(24, 96), 20)
	_label("挥斧：横向砍击", Vector2(520, 96), 20)
	var actions: Texture2D = load("res://assets/generated/characters/farmer_actions_v3.png") as Texture2D
	_sprite(actions, Vector2(24, 128), 3, Rect2(0, 0, 128, 32))
	_sprite(actions, Vector2(520, 128), 3, Rect2(0, 128, 128, 32))
	_label("后续作物：种子 → 幼苗 → 生长 → 成熟 → 收获", Vector2(24, 240), 20)
	_sprite(load("res://assets/generated/crops/crop_growth_v1.png"), Vector2(24, 280), 3)
	_label("种子袋与资源物品", Vector2(664, 240), 20)
	_sprite(load("res://assets/generated/items/farm_items_v1.png"), Vector2(664, 288), 4)
	_label("胡萝卜 / 芜菁 / 番茄 / 小麦", Vector2(24, 680), 18)
	_label("木材、石头、纤维、肥料", Vector2(664, 568), 18)
	_label("收获物、金币、出货袋、木箱", Vector2(664, 600), 18)
	_label("动作与种子图标已接入；作物生长、背包、出售图片先行备齐。", Vector2(24, 720), 18)
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://docs/screenshots/farm-assets-preview.png"
	viewport.get_texture().get_image().save_png(path)
	print("[farm_art_preview] " + ProjectSettings.globalize_path(path))
	quit(0)


func _label(text: String, position: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("594954"))
	_canvas.add_child(label)


func _sprite(texture: Texture2D, position: Vector2, zoom: float, region: Rect2 = Rect2()) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = position
	sprite.scale = Vector2.ONE * zoom
	if region.has_area():
		sprite.region_enabled = true
		sprite.region_rect = region
	_canvas.add_child(sprite)
