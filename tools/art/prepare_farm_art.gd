extends SceneTree
## 生成图的技术整理：均分切片、最近邻缩放、二值 Alpha、统一落脚点。
## 原始生成文件始终保存在 sources，不覆盖原素材。

const ROOT := "res://assets/generated/"
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const CROPS: Array[String] = ["carrot", "turnip", "tomato", "wheat"]
const STAGES: Array[String] = ["seeds", "sprout", "young", "growing", "mature", "harvest"]
const ITEMS: Array[String] = [
	"carrot_seeds", "turnip_seeds", "tomato_seeds", "wheat_seeds",
	"wood", "stone", "fiber", "fertilizer",
	"carrot", "turnip", "tomato", "wheat",
	"coin", "coins", "shipping_sack", "chest",
]


func _init() -> void:
	var actions: Image = Image.load_from_file(ProjectSettings.globalize_path(ROOT + "sources/farmer_actions_v3.png"))
	var crops: Image = Image.load_from_file(ProjectSettings.globalize_path(ROOT + "sources/crop_growth_v1.png"))
	var items: Image = Image.load_from_file(ProjectSettings.globalize_path(ROOT + "sources/farm_items_v1.png"))
	if actions == null or crops == null or items == null:
		quit(1)
		return
	var action_atlas: Image = _canvas(128, 256)
	for row in 8:
		var tool: String = "hoe" if row < 4 else "axe"
		for column in 4:
			var frame: Image = _action_frame(_cell(actions, column, row, 4, 8))
			action_atlas.blit_rect(frame, Rect2i(0, 0, 32, 32), Vector2i(column, row) * 32)
			frame.save_png(ROOT + "characters/%s_%s_%d.png" % [tool, DIRECTIONS[row % 4], column])
	action_atlas.save_png(ROOT + "characters/farmer_actions_v3.png")
	var crop_atlas: Image = _canvas(192, 128)
	for row in 4:
		for column in 6:
			var frame: Image = _cell(crops, column, row, 6, 4)
			frame.resize(32, 32, Image.INTERPOLATE_NEAREST)
			var bounds: Rect2i = frame.get_used_rect()
			var aligned: Image = _canvas(32, 32)
			aligned.blit_rect(frame, bounds, Vector2i((32 - bounds.size.x) / 2, 31 - bounds.size.y))
			crop_atlas.blit_rect(aligned, Rect2i(0, 0, 32, 32), Vector2i(column, row) * 32)
			aligned.save_png(ROOT + "crops/%s_%s.png" % [CROPS[row], STAGES[column]])
	crop_atlas.save_png(ROOT + "crops/crop_growth_v1.png")
	var item_atlas: Image = _canvas(64, 64)
	for index in ITEMS.size():
		var frame: Image = _cell(items, index % 4, index / 4, 4, 4)
		frame = frame.get_region(frame.get_used_rect())
		var factor: float = 14.0 / maxf(frame.get_width(), frame.get_height())
		frame.resize(maxi(1, roundi(frame.get_width() * factor)), maxi(1, roundi(frame.get_height() * factor)), Image.INTERPOLATE_NEAREST)
		var aligned: Image = _canvas(16, 16)
		aligned.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), (Vector2i(16, 16) - frame.get_size()) / 2)
		item_atlas.blit_rect(aligned, Rect2i(0, 0, 16, 16), Vector2i(index % 4, index / 4) * 16)
		aligned.save_png(ROOT + "items/%s.png" % ITEMS[index])
	item_atlas.save_png(ROOT + "items/farm_items_v1.png")
	var soil: Image = load("res://scripts/world/soil_autotile.gd").make_atlas_image()
	soil.save_png(ROOT + "terrain/soil_dry_atlas.png")
	for y in soil.get_height():
		for x in soil.get_width():
			soil.set_pixel(x, y, soil.get_pixel(x, y) * Color(0.70, 0.62, 0.54, 1.0))
	soil.save_png(ROOT + "terrain/soil_wet_atlas.png")
	var manifest := {
		"generator": "built-in image_gen; technical preparation: tools/art/prepare_farm_art.gd",
		"sources": "sources/* (original generated images, retained)",
		"actions": {"path": "characters/farmer_actions_v3.png", "cell": [32, 32], "columns": 4, "rows": ["hoe_down", "hoe_up", "hoe_left", "hoe_right", "axe_down", "axe_up", "axe_left", "axe_right"], "frames": ["ready", "anticipation", "impact", "recovery"], "feet": [16, 24]},
		"crops": {"path": "crops/crop_growth_v1.png", "cell": [32, 32], "rows": CROPS, "columns": STAGES, "root_y": 31, "status": "art ready; growth gameplay pending"},
		"items": {"path": "items/farm_items_v1.png", "cell": [16, 16], "columns": 4, "order": ITEMS, "status": "carrot_seeds used in toolbar; other icons reserved"},
		"alpha": "binary 0/255; nearest texture filtering",
	}
	var file := FileAccess.open(ROOT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("[prepare_farm_art] 32 action poses + 24 crop sprites + 16 item icons saved")
	quit(0)


func _canvas(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _cell(source: Image, x: int, y: int, columns: int, rows: int) -> Image:
	var start := Vector2i(roundi(float(x * source.get_width()) / columns), roundi(float(y * source.get_height()) / rows))
	var end := Vector2i(roundi(float((x + 1) * source.get_width()) / columns), roundi(float((y + 1) * source.get_height()) / rows))
	var frame: Image = source.get_region(Rect2i(start, end - start))
	# 生成源图包含近乎透明的背景 RGB；像素素材按硬边 Alpha 导入。
	for py in frame.get_height():
		for px in frame.get_width():
			var color: Color = frame.get_pixel(px, py)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			frame.set_pixel(px, py, color if color.a > 0 else Color.TRANSPARENT)
	return frame


func _action_frame(frame: Image) -> Image:
	# 用角色奶黄色身体定位，排除工具，统一角色大小与脚底基线。
	var body := Rect2i()
	for y in frame.get_height():
		for x in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			if color.a > 0 and color.r > 0.7 and color.g > 0.65 and color.r > color.g + 0.015 and color.g > color.b + 0.08:
				if body.size == Vector2i.ZERO:
					body = Rect2i(x, y, 1, 1)
				else:
					body = body.expand(Vector2i(x, y))
	if body.size.y == 0:
		push_error("[prepare_farm_art] character body not found")
		return _canvas(32, 32)
	var factor: float = 14.0 / body.size.y
	var new_size := Vector2i(roundi(frame.get_width() * factor), roundi(frame.get_height() * factor))
	frame.resize(new_size.x, new_size.y, Image.INTERPOLATE_NEAREST)
	var offset := Vector2i(16 - roundi(body.get_center().x * factor), 23 - roundi(body.end.y * factor))
	var aligned: Image = _canvas(32, 32)
	aligned.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), offset)
	return aligned
