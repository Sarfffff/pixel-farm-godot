extends SceneTree
## 将 ImageGen 原图技术整理为透明像素素材；不覆盖现有作物或动物。
## godot --headless --path . --script res://tools/art/prepare_expansion_art.gd

const ROOT: String = "res://assets/generated/expansion_v1/"
const SOURCE: String = "res://assets/generated/sources/"
const FISH: Array[String] = [
	"crucian_carp", "common_carp", "bluegill", "largemouth_bass",
	"rainbow_trout", "perch", "catfish", "northern_pike",
	"red_koi", "goldfish", "salmon", "freshwater_eel",
]
const GEAR: Array[String] = [
	"bamboo_rod", "wooden_rod", "steel_rod", "master_rod",
	"bobber", "worm_bait", "brass_lure", "tackle_box",
]
const CROPS: Array[String] = ["potato", "corn", "strawberry", "pumpkin", "cabbage", "eggplant"]
const STAGES: Array[String] = ["seeds", "sprout", "young", "growing", "mature", "harvest"]
const ANIMALS: Array[String] = ["duck", "sheep", "pig", "goat", "rabbit", "horse"]
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const LABELS: Dictionary = {
	"crucian_carp": "鲫鱼", "common_carp": "鲤鱼", "bluegill": "蓝鳃太阳鱼", "largemouth_bass": "大口黑鲈",
	"rainbow_trout": "虹鳟", "perch": "河鲈", "catfish": "鲶鱼", "northern_pike": "白斑狗鱼",
	"red_koi": "红白锦鲤", "goldfish": "金鱼", "salmon": "鲑鱼", "freshwater_eel": "淡水鳗鱼",
	"bamboo_rod": "竹鱼竿", "wooden_rod": "木鱼竿", "steel_rod": "钢鱼竿", "master_rod": "大师鱼竿",
	"bobber": "浮漂", "worm_bait": "蚯蚓饵", "brass_lure": "黄铜拟饵", "tackle_box": "渔具箱",
	"potato": "土豆", "corn": "玉米", "strawberry": "草莓", "pumpkin": "南瓜", "cabbage": "卷心菜", "eggplant": "茄子",
	"duck": "鸭", "sheep": "绵羊", "pig": "猪", "goat": "山羊", "rabbit": "兔", "horse": "马",
}
const STAGE_LABELS: Dictionary = {"seeds": "种子袋", "sprout": "发芽", "young": "幼苗", "growing": "生长", "mature": "成熟", "harvest": "收获物"}

var _entries: Array[Dictionary] = []
var _errors: int = 0


func _init() -> void:
	for folder: String in ["fish", "fishing", "crops", "animals", "icons", "atlases"]:
		DirAccess.make_dir_recursive_absolute(ROOT + folder)
	_items("fish_icons_v1.png", FISH, 4, 3, "fish")
	_items("fishing_gear_v1.png", GEAR, 4, 2, "fishing")
	_crops()
	_animals()
	for entry: Dictionary in _entries:
		entry["display_name"] = str(LABELS[entry["crop"]]) + " · " + str(STAGE_LABELS[entry["stage"]]) if entry["category"] == "crop" else LABELS[entry["id"]]
	var file: FileAccess = FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": 1,
		"generator": "built-in image_gen; technical preparation: tools/art/prepare_expansion_art.gd",
		"filter": "nearest; no mipmaps",
		"alpha": "original sources preserved; runtime sprites use binary alpha",
		"status": "art assets only; no fishing, crop growth or animal AI gameplay added",
		"items": _entries,
	}, "\t") + "\n")
	print("[expansion_art] %d catalog entries, %d errors" % [_entries.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _load_source(name: String) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + name))
	if image == null:
		_errors += 1
		push_error("[expansion_art] Missing source: " + name)
	return image


func _cell(image: Image, column: int, row: int, columns: int, rows: int) -> Image:
	var start: Vector2i = Vector2i(roundi(float(image.get_width() * column) / columns), roundi(float(image.get_height() * row) / rows))
	var end: Vector2i = Vector2i(roundi(float(image.get_width() * (column + 1)) / columns), roundi(float(image.get_height() * (row + 1)) / rows))
	var frame: Image = image.get_region(Rect2i(start, end - start))
	# 与已有 prepare_farm_art.gd 相同的硬边 Alpha；清除生成图的半透明毛边。
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			color.a = 1.0 if color.a >= 0.5 else 0.0
			frame.set_pixel(x, y, color if color.a > 0 else Color.TRANSPARENT)
	_remove_neighbor_fragments(frame)
	return frame


func _remove_neighbor_fragments(frame: Image) -> void:
	# 生成图的等分边界可能切到邻格的一小截。保留主体及紧邻主体的独立细节。
	var width: int = frame.get_width()
	var height: int = frame.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var components: Array[Dictionary] = []
	var largest: int = -1
	var largest_area: int = 0
	for y: int in height:
		for x: int in width:
			var start: int = y * width + x
			if visited[start] != 0 or frame.get_pixel(x, y).a == 0:
				continue
			var pixels: PackedInt32Array = PackedInt32Array([start])
			visited[start] = 1
			var bounds: Rect2i = Rect2i(x, y, 1, 1)
			var index: int = 0
			while index < pixels.size():
				var pixel: int = pixels[index]
				index += 1
				var point: Vector2i = Vector2i(pixel % width, pixel / width)
				bounds = bounds.expand(point)
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var next: Vector2i = point + Vector2i(dx, dy)
						if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
							continue
						var next_index: int = next.y * width + next.x
						if visited[next_index] == 0 and frame.get_pixelv(next).a > 0:
							visited[next_index] = 1
							pixels.append(next_index)
			components.append({"pixels": pixels, "bounds": bounds})
			if pixels.size() > largest_area:
				largest_area = pixels.size()
				largest = components.size() - 1
	if largest < 0:
		return
	var keep_region: Rect2i = (components[largest]["bounds"] as Rect2i).grow(maxi(3, mini(width, height) / 40))
	for component: Dictionary in components:
		if keep_region.intersects(component["bounds"]):
			continue
		for pixel: int in component["pixels"]:
			frame.set_pixel(pixel % width, pixel / width, Color.TRANSPARENT)


func _canvas(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _fit(frame: Image, size: int, extent: int, baseline: int = -1, scale_factor: float = -1.0) -> Image:
	var bounds: Rect2i = frame.get_used_rect()
	var result: Image = _canvas(Vector2i(size, size))
	if bounds.size == Vector2i.ZERO:
		_errors += 1
		push_error("[expansion_art] Empty sprite")
		return result
	var crop: Image = frame.get_region(bounds)
	var factor: float = float(extent) / maxi(bounds.size.x, bounds.size.y) if scale_factor < 0 else scale_factor
	crop.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
	var position: Vector2i = Vector2i((size - crop.get_width()) / 2, (size - crop.get_height()) / 2)
	if baseline >= 0:
		position.y = baseline + 1 - crop.get_height()
	result.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), position)
	return result


func _save(image: Image, relative_path: String) -> void:
	var error: Error = image.save_png(ROOT + relative_path)
	if error != OK:
		_errors += 1
		push_error("[expansion_art] Save failed: " + relative_path)


func _items(source_name: String, names: Array[String], columns: int, rows: int, category: String) -> void:
	var source: Image = _load_source(source_name)
	if source == null:
		return
	var atlas: Image = _canvas(Vector2i(columns, rows) * 32)
	for index: int in names.size():
		var frame: Image = _cell(source, index % columns, index / columns, columns, rows)
		var sprite: Image = _fit(frame, 32, 28)
		var path: String = "%s/%s.png" % [category, names[index]]
		var icon_path: String = "icons/%s.png" % names[index]
		_save(sprite, path)
		_save(_fit(frame, 16, 14), icon_path)
		atlas.blit_rect(sprite, Rect2i(0, 0, 32, 32), Vector2i(index % columns, index / columns) * 32)
		_entries.append({"id": names[index], "category": category, "path": path, "size": [32, 32], "icon": icon_path,
			"atlas": "atlases/%s.png" % category, "atlas_cell": [index % columns, index / columns]})
	_save(atlas, "atlases/%s.png" % category)


func _crops() -> void:
	var source: Image = _load_source("crops_expansion_v1.png")
	if source == null:
		return
	var atlas: Image = _canvas(Vector2i(192, 192))
	for row: int in CROPS.size():
		for column: int in STAGES.size():
			var frame: Image = _cell(source, column, row, 6, 6)
			# 生长阶段使用递增的尺寸预算，避免小芽与成熟植株同样大。
			var extent: int = [18, 9, 15, 22, 28, 22][column]
			var sprite: Image = _fit(frame, 32, extent, 30)
			var path: String = "crops/%s_%s.png" % [CROPS[row], STAGES[column]]
			_save(sprite, path)
			atlas.blit_rect(sprite, Rect2i(0, 0, 32, 32), Vector2i(column, row) * 32)
			var entry: Dictionary = {"id": "%s_%s" % [CROPS[row], STAGES[column]], "category": "crop", "crop": CROPS[row],
				"stage": STAGES[column], "path": path, "size": [32, 32], "root": [16, 31],
				"atlas": "atlases/crops.png", "atlas_cell": [column, row]}
			if column == 0 or column == 5:
				var icon: String = "icons/%s%s.png" % [CROPS[row], "_seeds" if column == 0 else ""]
				_save(_fit(frame, 16, 14), icon)
				entry["icon"] = icon
			_entries.append(entry)
	_save(atlas, "atlases/crops.png")


func _animals() -> void:
	var source: Image = _load_source("animals_expansion_v1.png")
	if source == null:
		return
	for row: int in ANIMALS.size():
		var frames: Array[Image] = []
		var largest: int = 1
		for column: int in 4:
			var frame: Image = _cell(source, column, row, 4, 6)
			frames.append(frame)
			var bounds: Rect2i = frame.get_used_rect()
			largest = maxi(largest, maxi(bounds.size.x, bounds.size.y))
		var size: int = 48 if ANIMALS[row] == "horse" else 32
		var baseline: int = size - 4
		var factor: float = float(size - 8) / largest
		var sheet: Image = _canvas(Vector2i(size * 4, size))
		var paths: Dictionary = {}
		for column: int in 4:
			var sprite: Image = _fit(frames[column], size, size - 8, baseline, factor)
			var path: String = "animals/%s_%s.png" % [ANIMALS[row], DIRECTIONS[column]]
			_save(sprite, path)
			sheet.blit_rect(sprite, Rect2i(0, 0, size, size), Vector2i(column * size, 0))
			paths[DIRECTIONS[column]] = path
		_save(sheet, "animals/%s_directions.png" % ANIMALS[row])
		_entries.append({"id": ANIMALS[row], "category": "animal", "size": [size, size], "feet": [size / 2, baseline + 1],
			"directions": DIRECTIONS, "frames": paths, "atlas": "animals/%s_directions.png" % ANIMALS[row],
			"animation": "four idle directions only; walk/eat animations not included"})
