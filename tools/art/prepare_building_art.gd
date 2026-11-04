extends SceneTree

const ROOT: String = "res://assets/textures/buildings/"
const SOURCE: String = "res://art/sources/base/"
const PREVIEW: String = "res://art/previews/buildings/preview.png"
const PALETTE: Array[Color] = [
	Color("302421"), Color("654638"), Color("936644"), Color("bc8757"),
	Color("dcb272"), Color("f0e1b6"), Color("ceba88"), Color("596b4b"),
	Color("839568"), Color("484f58"), Color("747f86"), Color("aab2b3"),
	Color("415d76"), Color("7fa8bc"), Color("9c484b"), Color("cc7c58"),
]
const BUILDINGS: Array[Dictionary] = [
	{"id": "timber_cottage", "label": "原木小屋", "category": "residential", "sheet": "village_houses_a_v1.png", "cell": Vector2i(0, 0), "size": Vector2i(64, 64)},
	{"id": "stone_cottage", "label": "石砌小屋", "category": "residential", "sheet": "village_houses_a_v1.png", "cell": Vector2i(1, 0), "size": Vector2i(64, 64)},
	{"id": "half_timber_house", "label": "木梁民居", "category": "residential", "sheet": "village_houses_a_v1.png", "cell": Vector2i(0, 1), "size": Vector2i(64, 64)},
	{"id": "family_house", "label": "双层家庭住宅", "category": "residential", "sheet": "village_houses_a_v1.png", "cell": Vector2i(1, 1), "size": Vector2i(64, 64)},
	{"id": "duplex_house", "label": "双户联排住宅", "category": "residential", "sheet": "village_houses_clinics_v1.png", "cell": Vector2i(0, 0), "size": Vector2i(96, 80)},
	{"id": "country_manor", "label": "乡村大宅", "category": "residential", "sheet": "village_houses_clinics_v1.png", "cell": Vector2i(1, 0), "size": Vector2i(96, 96)},
	{"id": "village_hospital", "label": "村医院", "category": "facilities", "sheet": "village_houses_clinics_v1.png", "cell": Vector2i(0, 1), "size": Vector2i(96, 80)},
	{"id": "veterinary_clinic", "label": "兽医诊所", "category": "facilities", "sheet": "village_houses_clinics_v1.png", "cell": Vector2i(1, 1), "size": Vector2i(64, 64)},
	{"id": "village_school", "label": "村学校", "category": "facilities", "sheet": "village_services_v1.png", "cell": Vector2i(0, 0), "size": Vector2i(96, 96)},
	{"id": "library", "label": "图书馆", "category": "facilities", "sheet": "village_services_v1.png", "cell": Vector2i(1, 0), "size": Vector2i(96, 96)},
	{"id": "community_center", "label": "社区活动中心", "category": "facilities", "sheet": "village_services_v1.png", "cell": Vector2i(0, 1), "size": Vector2i(96, 80)},
	{"id": "general_store", "label": "杂货店", "category": "facilities", "sheet": "village_services_v1.png", "cell": Vector2i(1, 1), "size": Vector2i(64, 64)},
	{"id": "seed_shop", "label": "种子园艺店", "category": "facilities", "sheet": "village_workshops_v1.png", "cell": Vector2i(0, 0), "size": Vector2i(64, 64)},
	{"id": "blacksmith", "label": "铁匠铺", "category": "facilities", "sheet": "village_workshops_v1.png", "cell": Vector2i(1, 0), "size": Vector2i(96, 80)},
	{"id": "carpenter", "label": "木工坊", "category": "facilities", "sheet": "village_workshops_v1.png", "cell": Vector2i(0, 1), "size": Vector2i(96, 80)},
	{"id": "bakery", "label": "面包店", "category": "facilities", "sheet": "village_workshops_v1.png", "cell": Vector2i(1, 1), "size": Vector2i(64, 64)},
	{"id": "restaurant", "label": "村餐馆", "category": "facilities", "sheet": "village_life_v1.png", "cell": Vector2i(0, 0), "size": Vector2i(96, 80)},
	{"id": "country_inn", "label": "乡村旅馆", "category": "facilities", "sheet": "village_life_v1.png", "cell": Vector2i(1, 0), "size": Vector2i(96, 96)},
	{"id": "bathhouse", "label": "公共浴场", "category": "facilities", "sheet": "village_life_v1.png", "cell": Vector2i(0, 1), "size": Vector2i(96, 80)},
	{"id": "market_hall", "label": "集市大厅", "category": "facilities", "sheet": "village_life_v1.png", "cell": Vector2i(1, 1), "size": Vector2i(96, 96)},
]

var _sources: Dictionary[String, Image] = {}
var _entries: Array[Dictionary] = []
var _errors: int = 0
var _preview: Image = Image.create(560, 448, false, Image.FORMAT_RGBA8)


func _init() -> void:
	if "--verify-only" in OS.get_cmdline_user_args():
		_verify_imports()
		quit(0 if _errors == 0 else 1)
		return
	for folder: String in ["residential", "facilities", "icons"]:
		if DirAccess.make_dir_recursive_absolute(ROOT + folder) != OK:
			_fail("Cannot create directory: " + folder)
	if _errors > 0:
		quit(1)
		return
	_preview.fill(Color.TRANSPARENT)
	for index: int in BUILDINGS.size():
		_prepare_building(BUILDINGS[index], index)
	if _entries.size() != 20:
		_fail("Expected 20 buildings")
	if _errors == 0:
		_save_catalog()
		_preview.resize(1680, 1344, Image.INTERPOLATE_NEAREST)
		DirAccess.make_dir_recursive_absolute(PREVIEW.get_base_dir())
		if _preview.save_png(PREVIEW) != OK:
			_fail("Cannot save preview")
	print("[building_art] %d buildings, %d icons, %d errors" % [_entries.size(), _entries.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _fail(message: String) -> void:
	_errors += 1
	push_error("[building_art] " + message)


func _source(name: String) -> Image:
	if _sources.has(name):
		return _sources[name]
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + name))
	if image == null:
		_fail("Missing source: " + name)
		return null
	image.convert(Image.FORMAT_RGBA8)
	_sources[name] = image
	return image


func _extract(source: Image, cell: Vector2i) -> Image:
	var cell_size: Vector2i = source.get_size() / 2
	var frame: Image = source.get_region(Rect2i(cell * cell_size, cell_size))
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			var background: bool = color.r > 0.7 and color.b > 0.65 and color.g < 0.4
			var fringe: bool = color.r > color.g + 0.23 and color.b > color.g + 0.23 and color.r + color.b > 1.2
			if color.a < 0.5 or background or fringe:
				frame.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				frame.set_pixel(x, y, color)
	_keep_building(frame)
	return frame


func _keep_building(image: Image) -> void:
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


func _fit(frame: Image, canvas_size: Vector2i, grounded: bool) -> Image:
	var result: Image = Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var bounds: Rect2i = frame.get_used_rect()
	if bounds.size == Vector2i.ZERO:
		_fail("Empty building source")
		return result
	var crop: Image = frame.get_region(bounds)
	var extent: Vector2i = canvas_size - Vector2i(4, 3)
	var factor: float = minf(float(extent.x) / bounds.size.x, float(extent.y) / bounds.size.y)
	crop.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
	var position: Vector2i = Vector2i((canvas_size.x - crop.get_width()) / 2, (canvas_size.y - crop.get_height()) / 2)
	if grounded:
		position.y = canvas_size.y - crop.get_height()
	result.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), position)
	for y: int in canvas_size.y:
		for x: int in canvas_size.x:
			var color: Color = result.get_pixel(x, y)
			result.set_pixel(x, y, _nearest_color(color) if color.a >= 0.5 else Color.TRANSPARENT)
	return result


func _prepare_building(definition: Dictionary, index: int) -> void:
	var source_name: String = str(definition["sheet"])
	var source: Image = _source(source_name)
	if source == null:
		return
	var id: String = str(definition["id"])
	var category: String = str(definition["category"])
	var size: Vector2i = definition["size"]
	var cell: Vector2i = definition["cell"]
	var frame: Image = _extract(source, cell)
	var exterior: Image = _fit(frame, size, true)
	var icon: Image = _fit(frame, Vector2i(32, 32), false)
	var exterior_path: String = ROOT + "%s/%s.png" % [category, id]
	var icon_path: String = ROOT + "icons/%s.png" % id
	if exterior.save_png(exterior_path) != OK or icon.save_png(icon_path) != OK:
		_fail("Cannot save: " + id)
		return
	var preview_cell: Vector2i = Vector2i(index % 5, index / 5)
	var preview_position: Vector2i = preview_cell * 112 + Vector2i((112 - size.x) / 2, 108 - size.y)
	_preview.blit_rect(exterior, Rect2i(Vector2i.ZERO, size), preview_position)
	var bounds: Rect2i = exterior.get_used_rect()
	_entries.append({
		"id": id, "display_name": definition["label"], "category": category,
		"exterior": exterior_path, "icon": icon_path, "size": [size.x, size.y], "icon_size": [32, 32],
		"baseline": size.y - 1, "anchor": [size.x / 2, size.y - 1], "sprite_offset": [0, -size.y / 2],
		"opaque_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"canvas_tiles": [size.x / 16, size.y / 16], "preview_cell": [preview_cell.x, preview_cell.y],
		"source": SOURCE + source_name, "source_cell": [cell.x, cell.y],
	})


func _save_catalog() -> void:
	var file: FileAccess = FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	if file == null:
		_fail("Cannot save catalog")
		return
	var palette: Array[String] = []
	for color: Color in PALETTE:
		palette.append("#" + color.to_html(false))
	file.store_string(JSON.stringify({
		"version": 1, "generator": "image_gen; technical preparation: tools/art/prepare_building_art.gd",
		"status": "exterior art only; no interiors, door animation, scene placement, collision, NPCs or service logic",
		"building_count": _entries.size(), "texture_count": _entries.size() * 2,
		"residential_count": 6, "facility_count": 14, "palette": palette,
		"sampling": "nearest, no mipmaps", "alpha": [0, 255], "map_tile_size": 16,
		"preview": PREVIEW, "buildings": _entries,
		"placement": "Centered Sprite2D with listed sprite_offset anchors the bottom at the node origin. Canvas tile dimensions are visual size, NOT collision footprint. Facade and doorway collisions must be authored later; do not block the whole roof rectangle.",
	}, "\t") + "\n")


func _verify_imports() -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(ROOT + "catalog.json")) != OK or not json.data is Dictionary:
		_fail("Cannot read catalog")
		return
	var catalog: Dictionary = json.data
	var entries: Array[Dictionary] = []
	entries.assign(catalog.get("buildings", []))
	if entries.size() != 20:
		_fail("Expected 20 building entries")
	var loaded: int = 0
	for entry: Dictionary in entries:
		for kind: String in ["exterior", "icon"]:
			var path: String = str(entry[kind])
			var texture: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
			if texture == null:
				_fail("Cannot load: " + path)
				continue
			var dimensions: Array[int] = []
			dimensions.assign(entry["size" if kind == "exterior" else "icon_size"])
			var expected: Vector2i = Vector2i(dimensions[0], dimensions[1])
			if Vector2i(texture.get_size()) != expected:
				_fail("Imported size mismatch: " + path)
			var image: Image = texture.get_image()
			if image == null or image.is_empty() or image.get_used_rect().size == Vector2i.ZERO:
				_fail("Imported image empty: " + path)
				continue
			if image.has_mipmaps():
				_fail("Unexpected mipmaps: " + path)
			for y: int in image.get_height():
				for x: int in image.get_width():
					var color: Color = image.get_pixel(x, y)
					if color.a != 0.0 and color.a != 1.0:
						_fail("Non-binary alpha: " + path)
			loaded += 1
	print("[building_art_import] %d/40 textures loaded, %d errors" % [loaded, _errors])
