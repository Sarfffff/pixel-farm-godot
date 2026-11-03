extends SceneTree

const ROOT: String = "res://assets/generated/"
const SOURCE: String = ROOT + "sources/"
const PALETTE: Array[Color] = [
	Color("302421"), Color("654638"), Color("936644"), Color("dcb272"),
	Color("f0e1b6"), Color("344b3f"), Color("596b4b"), Color("839568"),
	Color("a9ba85"), Color("9c3848"), Color("db6552"), Color("ec9a48"),
	Color("e4cb55"), Color("51425f"), Color("926da0"), Color("607aa0"),
]
const SHEETS: Array[Dictionary] = [
	{
		"source": "orchard_a_v1.png", "category": "orchard",
		"species": ["apple", "pear", "peach", "cherry"],
		"labels": ["苹果", "梨", "桃", "樱桃"],
		"columns": [0, 145, 320, 533, 754, 905, 1024],
		"rows": [0, 256, 512, 768, 1024],
	},
	{
		"source": "orchard_b_v1.png", "category": "orchard",
		"species": ["orange", "lemon", "fig", "persimmon"],
		"labels": ["橙子", "柠檬", "无花果", "柿子"],
		"columns": [0, 125, 310, 522, 730, 900, 1024],
		"rows": [0, 256, 512, 768, 1024],
	},
	{
		"source": "berry_shrubs_v1.png", "category": "berry",
		"species": ["blueberry", "raspberry", "blackberry", "gooseberry"],
		"labels": ["蓝莓", "覆盆子", "黑莓", "醋栗"],
		"columns": [0, 132, 360, 630, 890, 1024],
		"rows": [0, 256, 512, 768, 1024],
	},
	{
		"source": "fruit_vines_v1.png", "category": "mixed",
		"species": ["goji", "grape", "kiwi", "passionfruit"],
		"labels": ["枸杞", "葡萄", "猕猴桃", "百香果"],
		"columns": [0, 200, 407, 632, 857, 1024],
		"rows": [0, 209, 492, 767, 1024],
	},
]

var _entries: Array[Dictionary] = []
var _groups: Array[Dictionary] = []
var _errors: int = 0
var _preview: Image = Image.create(192, 544, false, Image.FORMAT_RGBA8)


func _init() -> void:
	if "--verify-only" in OS.get_cmdline_user_args():
		_validate_imports()
		quit(0 if _errors == 0 else 1)
		return
	_preview.fill(Color.TRANSPARENT)
	for folder: String in ["trees", "items", "field"]:
		var error: Error = DirAccess.make_dir_recursive_absolute(ROOT + folder)
		if error != OK:
			_fail("Cannot create directory: " + folder)
	if _errors > 0:
		quit(1)
		return
	for sheet: Dictionary in SHEETS:
		_prepare_sheet(sheet)
	_prepare_props()
	if _entries.size() != 101:
		_fail("Expected 101 textures, got %d" % _entries.size())
	if _errors == 0:
		_write_catalog()
		_preview.resize(768, 2176, Image.INTERPOLATE_NEAREST)
		var error: Error = _preview.save_png(ROOT + "trees/preview.png")
		if error != OK:
			_fail("Cannot save preview")
	print("[tree_art] %d textures, %d varieties, %d errors" % [_entries.size(), _groups.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _fail(message: String) -> void:
	_errors += 1
	push_error("[tree_art] " + message)


func _validate_imports() -> void:
	var path: String = ROOT + "trees/catalog.json"
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		_fail("Cannot parse catalog")
		return
	var catalog: Dictionary = json.data
	var entries: Array[Dictionary] = []
	entries.assign(catalog.get("textures", []))
	if entries.size() != 101:
		_fail("Expected 101 imported textures")
	var loaded: int = 0
	for entry: Dictionary in entries:
		var texture_path: String = str(entry["path"])
		var texture: Texture2D = ResourceLoader.load(texture_path, "Texture2D") as Texture2D
		if texture == null:
			_fail("Cannot load imported texture: " + texture_path)
			continue
		var expected: Vector2i = Vector2i(int(entry["size"][0]), int(entry["size"][1]))
		if Vector2i(texture.get_size()) != expected:
			_fail("Imported size mismatch: " + texture_path)
		var image: Image = texture.get_image()
		if image == null or image.is_empty() or image.get_used_rect().size == Vector2i.ZERO:
			_fail("Imported image is empty: " + texture_path)
			continue
		if image.has_mipmaps():
			_fail("Unexpected mipmaps: " + texture_path)
		for y: int in expected.y:
			for x: int in expected.x:
				var color: Color = image.get_pixel(x, y)
				if color.a != 0.0 and color.a != 1.0:
					_fail("Non-binary imported alpha: " + texture_path)
		loaded += 1
	print("[tree_art_import] %d/%d textures loaded, %d errors" % [loaded, entries.size(), _errors])


func _load_source(name: String) -> Image:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + name))
	if image == null:
		_fail("Missing source: " + name)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _cell(source: Image, rect: Rect2i, checkerboard: bool = false) -> Image:
	var image: Image = source.get_region(rect)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			var magenta: bool = color.r > 0.7 and color.b > 0.65 and color.g < 0.4
			var fringe: bool = color.r > color.g + 0.23 and color.b > color.g + 0.23 and color.r + color.b > 1.2
			var neutral: bool = checkerboard and minf(color.r, minf(color.g, color.b)) > 0.63 and color.s < 0.1
			if color.a < 0.5 or magenta or fringe or neutral:
				image.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				image.set_pixel(x, y, color)
	_keep_main_component(image)
	return image


func _keep_main_component(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(width * height)
	var components: Array[PackedInt32Array] = []
	var largest: int = -1
	var largest_size: int = 0
	for y: int in height:
		for x: int in width:
			var start: int = y * width + x
			if visited[start] != 0 or image.get_pixel(x, y).a == 0.0:
				continue
			var pixels: PackedInt32Array = PackedInt32Array([start])
			visited[start] = 1
			var index: int = 0
			while index < pixels.size():
				var point: Vector2i = Vector2i(pixels[index] % width, pixels[index] / width)
				index += 1
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var next: Vector2i = point + Vector2i(dx, dy)
						if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
							continue
						var next_index: int = next.y * width + next.x
						if visited[next_index] == 0 and image.get_pixelv(next).a > 0.0:
							visited[next_index] = 1
							pixels.append(next_index)
			components.append(pixels)
			if pixels.size() > largest_size:
				largest = components.size() - 1
				largest_size = pixels.size()
	for index: int in components.size():
		if index == largest:
			continue
		for pixel: int in components[index]:
			image.set_pixel(pixel % width, pixel / width, Color.TRANSPARENT)


func _nearest_color(color: Color) -> Color:
	var nearest: Color = PALETTE[0]
	var distance: float = INF
	for candidate: Color in PALETTE:
		var difference: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
		var candidate_distance: float = difference.length_squared()
		if candidate_distance < distance:
			distance = candidate_distance
			nearest = candidate
	return nearest


func _fit(frame: Image, canvas_size: Vector2i, extent: Vector2i, grounded: bool) -> Image:
	var image: Image = Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var bounds: Rect2i = frame.get_used_rect()
	if bounds.size == Vector2i.ZERO:
		_fail("Empty source cell")
		return image
	var crop: Image = frame.get_region(bounds)
	var factor: float = minf(float(extent.x) / bounds.size.x, float(extent.y) / bounds.size.y)
	crop.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
	var position: Vector2i = Vector2i((canvas_size.x - crop.get_width()) / 2, (canvas_size.y - crop.get_height()) / 2)
	if grounded:
		position.y = canvas_size.y - crop.get_height()
	image.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), position)
	for y: int in canvas_size.y:
		for x: int in canvas_size.x:
			var color: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, _nearest_color(color) if color.a >= 0.5 else Color.TRANSPARENT)
	return image


func _fruit_color(color: Color, species: String) -> bool:
	if species in ["pear", "lemon", "gooseberry"]:
		return color == PALETTE[12]
	if species == "peach":
		return color in [PALETTE[9], PALETTE[10], PALETTE[11]]
	if species in ["apple", "cherry", "raspberry"]:
		return color == PALETTE[9] or color == PALETTE[10]
	if species in ["orange", "persimmon", "goji"]:
		return color == PALETTE[10] or color == PALETTE[11]
	if species == "blueberry":
		return color == PALETTE[15]
	return color == PALETTE[13] or color == PALETTE[14]


func _foliage(color: Color) -> bool:
	return color in [PALETTE[5], PALETTE[6], PALETTE[7], PALETTE[8]]


func _harvested(ripe: Image, species: String) -> Image:
	var image: Image = ripe.duplicate() as Image
	var width: int = image.get_width()
	var height: int = image.get_height()
	var fruit: PackedByteArray = PackedByteArray()
	fruit.resize(width * height)
	for y: int in height:
		for x: int in width:
			if _fruit_color(ripe.get_pixel(x, y), species):
				fruit[y * width + x] = 1
	var mask: PackedByteArray = fruit.duplicate()
	for y: int in height:
		for x: int in width:
			if fruit[y * width + x] == 0:
				continue
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					var point: Vector2i = Vector2i(x + dx, y + dy)
					if point.x <= 0 or point.y <= 0 or point.x >= width - 1 or point.y >= height - 1:
						continue
					var color: Color = ripe.get_pixelv(point)
					if color.a > 0.0 and not color in [PALETTE[1], PALETTE[2], PALETTE[3]]:
						mask[point.y * width + point.x] = 1
	for y: int in height:
		for x: int in width:
			if mask[y * width + x] == 0:
				continue
			var nearest: Color = PALETTE[7]
			var distance: int = 2147483647
			for ny: int in height:
				for nx: int in width:
					if mask[ny * width + nx] != 0 or not _foliage(ripe.get_pixel(nx, ny)):
						continue
					var candidate_distance: int = (nx - x) * (nx - x) + (ny - y) * (ny - y)
					if candidate_distance < distance:
						distance = candidate_distance
						nearest = ripe.get_pixel(nx, ny)
			image.set_pixel(x, y, nearest)
	return image


func _kiwi_ripe(bare: Image, source: Image) -> Image:
	var image: Image = bare.duplicate() as Image
	for y: int in 25:
		for x: int in range(3, 29):
			var color: Color = source.get_pixel(x, y)
			if _foliage(bare.get_pixel(x, y)) and color in [PALETTE[1], PALETTE[2], PALETTE[3]]:
				image.set_pixel(x, y, color)
	return image


func _prepare_sheet(sheet: Dictionary) -> void:
	var source_name: String = str(sheet["source"])
	var source: Image = _load_source(source_name)
	if source == null:
		return
	var columns: Array[int] = []
	var rows: Array[int] = []
	columns.assign(sheet["columns"])
	rows.assign(sheet["rows"])
	for row: int in 4:
		var species: String = str(sheet["species"][row])
		var category: String = str(sheet["category"])
		if category == "mixed":
			category = "berry" if row == 0 else "vine"
		var frames: Array[Image] = []
		for column: int in 5:
			var rect: Rect2i = Rect2i(int(columns[column]), int(rows[row]), int(columns[column + 1]) - int(columns[column]), int(rows[row + 1]) - int(rows[row]))
			frames.append(_cell(source, rect, source_name == "orchard_a_v1.png"))
		if species == "persimmon":
			frames[4] = _cell(source, Rect2i(905, 768, 119, 122))
		if species == "fig":
			frames[4] = _cell(source, Rect2i(750, 512, 140, 122))
		if species == "lemon":
			frames[4] = _cell(source, Rect2i(750, 256, 140, 130))
		var extent: Vector2i = Vector2i(30, 30)
		if category == "berry":
			extent = Vector2i(30, 24)
		elif category == "vine":
			extent = Vector2i(20, 30)
		var ripe: Image = _fit(frames[2], Vector2i(32, 32), extent, true)
		var bare: Image = _harvested(ripe, species)
		if species == "kiwi":
			bare = _fit(frames[3], Vector2i(32, 32), extent, true)
			ripe = _kiwi_ripe(bare, ripe)
		var young_extent: Vector2i = Vector2i(20, 22)
		if category == "berry":
			young_extent = Vector2i(18, 14)
		elif category == "vine":
			young_extent = Vector2i(14, 22)
		var sapling: Image = _fit(frames[0], Vector2i(32, 32), Vector2i(12, 13), true)
		var young: Image = _fit(frames[1], Vector2i(32, 32), young_extent, true)
		if species != "kiwi":
			young = _harvested(young, species)
		var fruit_icon: Image = _fit(frames[4], Vector2i(16, 16), Vector2i(14, 14), false)
		var sapling_icon: Image = _fit(frames[0], Vector2i(16, 16), Vector2i(10, 14), false)
		var paths: Dictionary = {}
		var states: Array[String] = ["sapling", "young", "ripe", "bare"]
		var images: Array[Image] = [sapling, young, ripe, bare, fruit_icon, sapling_icon]
		var preview_row: int = _groups.size()
		for column: int in 6:
			var path: String = ""
			if column < 4:
				path = "trees/%s_%s.png" % [species, states[column]]
				paths[states[column]] = ROOT + path
			else:
				path = "items/%s%s.png" % [species, "_sapling" if column == 5 else ""]
				paths["sapling_item" if column == 5 else "fruit_item"] = ROOT + path
			_save(images[column], path, source_name, column < 4)
			var offset: Vector2i = Vector2i(column * 32, preview_row * 32)
			if column >= 4:
				offset += Vector2i(8, 8)
			_preview.blit_rect(images[column], Rect2i(Vector2i.ZERO, images[column].get_size()), offset)
		_groups.append({"id": species, "display_name": sheet["labels"][row], "category": category, "paths": paths, "root": [16, 31], "sprite_offset": [0, -16], "suggested_footprint": [2, 2] if category == "orchard" else ([1, 2] if category == "vine" else [1, 1])})


func _prepare_props() -> void:
	var source: Image = _load_source("planting_props_v1.png")
	if source == null:
		return
	var boundaries: Array[int] = [0, 253, 504, 751, 965, 1080]
	var names: Array[String] = ["trees/trellis_empty.png", "trees/trellis_vine.png", "trees/trellis_ripe.png", "field/planting_hole.png", "field/sapling_stake.png"]
	for index: int in 5:
		var start: int = roundi(float(source.get_width()) * boundaries[index] / 1080.0)
		var end: int = roundi(float(source.get_width()) * boundaries[index + 1] / 1080.0)
		var rect: Rect2i = Rect2i(start, 0, end - start, source.get_height())
		var frame: Image = _cell(source, rect)
		var size: Vector2i = Vector2i(16, 32) if index < 3 else Vector2i(16, 16)
		var extent: Vector2i = Vector2i(14, 30) if index < 3 else Vector2i(14, 14)
		var image: Image = _fit(frame, size, extent, true)
		_save(image, names[index], "planting_props_v1.png", true)
		_preview.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(index * 32 + 8, 512 + 32 - size.y))


func _save(image: Image, path: String, source: String, grounded: bool) -> void:
	if image.is_empty() or image.get_used_rect().size == Vector2i.ZERO:
		_fail("Empty output: " + path)
		return
	var error: Error = image.save_png(ROOT + path)
	if error != OK:
		_fail("Cannot save: " + path)
		return
	_entries.append({"path": ROOT + path, "size": [image.get_width(), image.get_height()], "grounded": grounded, "baseline": image.get_height() - 1 if grounded else -1, "source": SOURCE + source})


func _write_catalog() -> void:
	var file: FileAccess = FileAccess.open(ROOT + "trees/catalog.json", FileAccess.WRITE)
	if file == null:
		_fail("Cannot save catalog")
		return
	var colors: Array[String] = []
	for color: Color in PALETTE:
		colors.append("#" + color.to_html(false))
	file.store_string(JSON.stringify({
		"version": 1, "generator": "image_gen; technical preparation: tools/art/prepare_tree_art.gd",
		"status": "art only; no TreeData, gameplay, collision or inventory connections added",
		"texture_count": _entries.size(), "palette": colors, "alpha": [0, 255],
		"sampling": "nearest, no mipmaps", "preview": ROOT + "trees/preview.png",
		"root_collision_radius": [4, 5], "varieties": _groups, "textures": _entries,
		"preparation": "Background removal, measured source cells, nearest resize, shared 16-color palette; young sprites cleaned of premature fruit, harvested foliage inpainted over fruit pixels to preserve mature silhouette; sapling icons derived from planted saplings.",
	}, "\t") + "\n")
