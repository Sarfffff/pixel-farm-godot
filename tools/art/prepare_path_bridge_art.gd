extends SceneTree
## 整理ImageGen原图：裁切、硬Alpha、最近邻、现有色板与16px邻接掩码。

const Utils := preload("res://tools/lib/content_art_utils.gd")
const SOURCE: String = "res://art/sources/terrain_v2/bridges_and_path.png"
const BRIDGE: String = "res://assets/textures/terrain/river_bridge_atlas_v2.png"
const PATH: String = "res://assets/textures/terrain/farm_path_atlas.png"


func _init() -> void:
	var source: Image = Image.load_from_file(SOURCE)
	if source == null:
		quit(1)
		return
	var horizontal: Image = _sprite(source, Rect2i(28, 232, 387, 130), Vector2i(128, 32))
	var vertical: Image = _sprite(source, Rect2i(580, 84, 175, 425), Vector2i(32, 80))
	var bridge: Image = Utils.canvas(Vector2i(80, 48))
	for column: int in 3:
		var x: int = [0, 56, 112][column]
		bridge.blit_rect(horizontal, Rect2i(x, 0, 16, 32), Vector2i(column * 16, 0))
		bridge.blit_rect(horizontal, Rect2i(x, 16, 16, 16), Vector2i(column * 16, 32))
	for row: int in 3:
		bridge.blit_rect(vertical, Rect2i(0, [0, 32, 64][row], 32, 16), Vector2i(48, row * 16))
	var swatch: Image = source.get_region(Rect2i(52, 704, 336, 320))
	swatch.resize(16, 16, Image.INTERPOLATE_NEAREST)
	Utils.quantize(swatch, false)
	var paths: Image = Utils.canvas(Vector2i(64, 64))
	for mask: int in 16:
		for y: int in 16:
			for x: int in 16:
				if _inside_path(Vector2i(x, y), mask):
					paths.set_pixel(mask % 4 * 16 + x, mask / 4 * 16 + y, swatch.get_pixel(x, y))
	var error: Error = bridge.save_png(BRIDGE)
	if error == OK:
		error = paths.save_png(PATH)
	if error == OK:
		var preview: Image = Utils.canvas(Vector2i(176, 96))
		preview.blit_rect(horizontal, Rect2i(0, 0, 128, 32), Vector2i.ZERO)
		preview.blit_rect(vertical, Rect2i(0, 0, 32, 80), Vector2i(136, 0))
		preview.blit_rect(paths, Rect2i(0, 0, 64, 64), Vector2i(0, 32))
		preview.resize(704, 384, Image.INTERPOLATE_NEAREST)
		DirAccess.make_dir_recursive_absolute("res://art/previews/terrain_v2")
		error = preview.save_png("res://art/previews/terrain_v2/sheet.png")
	print("[path_bridge_art] bridge 80x48 and sixteen path variants 64x64; error=%d" % error)
	quit(0 if error == OK else 1)


func _sprite(source: Image, rect: Rect2i, size: Vector2i) -> Image:
	var crop: Image = source.get_region(rect)
	for y: int in crop.get_height():
		for x: int in crop.get_width():
			var color: Color = crop.get_pixel(x, y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			crop.set_pixel(x, y, color if color.a > 0.0 else Color.TRANSPARENT)
	Utils.remove_fragments(crop)
	crop = crop.get_region(crop.get_used_rect())
	crop.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	Utils.quantize(crop, false)
	return crop


func _inside_path(point: Vector2i, mask: int) -> bool:
	var x: int = point.x
	var y: int = point.y
	# 中心与四条连接臂；只有外露边缘留草地，连续铺地时接缝完整。
	if ((mask & 3) == 3 and x >= 8 and y < 8) \
		or ((mask & 6) == 6 and x >= 8 and y >= 8) \
		or ((mask & 12) == 12 and x < 8 and y >= 8) \
		or ((mask & 9) == 9 and x < 8 and y < 8):
		return true
	if x >= 2 and x < 14 and y >= 2 and y < 14:
		return not (x in [2, 13] and y in [2, 13])
	return ((mask & 1) != 0 and x >= 2 and x < 14 and y < 8) \
		or ((mask & 2) != 0 and y >= 2 and y < 14 and x >= 8) \
		or ((mask & 4) != 0 and x >= 2 and x < 14 and y >= 8) \
		or ((mask & 8) != 0 and y >= 2 and y < 14 and x < 8)
