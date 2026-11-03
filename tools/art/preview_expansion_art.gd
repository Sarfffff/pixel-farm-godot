extends SceneTree
## 用 Godot 实际渲染已导入的像素素材，输出带名称的素材总览。
## godot --path . --script res://tools/art/preview_expansion_art.gd

const Art := preload("res://tools/art/prepare_expansion_art.gd")
const ROOT: String = "res://assets/generated/expansion_v1/"
var _stage: Node2D
var _font: SystemFont


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1152, 1740)
	root.content_scale_size = Vector2i(1152, 1740)
	_stage = Node2D.new()
	root.add_child(_stage)
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei"])
	var background: ColorRect = ColorRect.new()
	background.size = Vector2(1152, 1740)
	background.color = Color("283d38")
	_stage.add_child(background)
	_label("PIXEL FARM · 钓鱼 / 作物 / 动物素材补充", Vector2(32, 20), 27)
	_label("透明 PNG · 最近邻像素 · 原生尺寸已统一 · 以下为放大预览", Vector2(32, 58), 15)
	_label("12 种鱼 · 32×32 场景素材 + 16×16 背包图标", Vector2(32, 94), 20)
	for index: int in Art.FISH.size():
		var point: Vector2 = Vector2(118 + (index % 6) * 184, 154 + (index / 6) * 100)
		_sprite("fish/" + Art.FISH[index] + ".png", point, 2.0)
		_label(Art.LABELS[Art.FISH[index]], point + Vector2(-76, 36), 15)
	_label("4 档鱼竿 + 浮漂 / 饵料 / 拟饵 / 渔具箱", Vector2(32, 328), 20)
	for index: int in Art.GEAR.size():
		var point: Vector2 = Vector2(88 + index * 140, 393)
		_sprite("fishing/" + Art.GEAR[index] + ".png", point, 2.0)
		_label(Art.LABELS[Art.GEAR[index]], point + Vector2(-52, 38), 15)
	_label("6 种作物 · 每种 6 阶段 · 32×32 / 脚底对齐", Vector2(32, 480), 20)
	for index: int in Art.STAGES.size():
		_label(Art.STAGE_LABELS[Art.STAGES[index]], Vector2(194 + index * 152, 520), 15)
	for row: int in Art.CROPS.size():
		_label(Art.LABELS[Art.CROPS[row]], Vector2(32, 567 + row * 66), 17)
		for column: int in 6:
			_sprite("crops/%s_%s.png" % [Art.CROPS[row], Art.STAGES[column]], Vector2(226 + column * 152, 574 + row * 66), 2.0)
	_label("6 种动物 · 四向站姿 · 32×32（马 48×48）", Vector2(32, 990), 20)
	for index: int in 4:
		_label(["朝下", "朝上", "朝左", "朝右"][index], Vector2(250 + index * 220, 1030), 16)
	for row: int in Art.ANIMALS.size():
		_label(Art.LABELS[Art.ANIMALS[row]], Vector2(32, 1080 + row * 100), 18)
		for column: int in 4:
			_sprite("animals/%s_%s.png" % [Art.ANIMALS[row], Art.DIRECTIONS[column]], Vector2(280 + column * 220, 1094 + row * 100), 2.0 if row == 5 else 3.0)
	_label("素材储备：动物为四向静态帧；尚未制作行走、进食或玩家抛竿动作。", Vector2(32, 1692), 16)
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(ROOT + "preview.png")
	print("[expansion_preview] saved %spreview.png (%d)" % [ROOT, error])
	_stage.queue_free()
	await process_frame
	quit(0 if error == OK else 1)


func _label(value: String, point: Vector2, size: int) -> void:
	var label: Label = Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.modulate = Color("e4dbb8")
	_stage.add_child(label)


func _sprite(path: String, point: Vector2, factor: float) -> void:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = load(ROOT + path) as Texture2D
	sprite.position = point
	sprite.scale = Vector2.ONE * factor
	_stage.add_child(sprite)
