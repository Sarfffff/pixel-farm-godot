extends SceneTree
## 内置 ImageGen 原图的技术整理；不改原图，统一画布、脚底和调色板。

const ROOT: String = "res://assets/packs/presentation_v3/"
const SOURCE: String = "res://art/sources/presentation_v3/"
const Utils = preload("res://tools/lib/content_art_utils.gd")
const Style = preload("res://tools/art/prepare_farm_style_art.gd")
const FURNITURE: Array[String] = ["single_bed", "bedside_table", "wardrobe", "armchair",
	"brick_fireplace", "bookcase", "floor_lamp", "rocking_chair", "wood_stool", "coffee_table",
	"wall_clock", "dining_table", "oak_chair", "refrigerator", "cupboard", "kitchen_table",
	"basket", "wood_chest", "display_cabinet", "wall_shelf", "tall_potted_tree", "potted_fern", "oval_rug", "square_rug"]
const STRUCTURES: Array[String] = ["farmhouse", "chicken_coop", "general_store", "community_center",
	"chest_closed", "chest_open", "preserves_idle", "preserves_working", "preserves_ready"]
const PEOPLE: Array[String] = ["shopkeeper", "gardener", "carpenter", "fisherman"]
const EMOTIONS: Array[String] = ["neutral", "happy", "concerned"]
const TILES: Array[String] = ["wood_floor", "wood_floor_alt", "wallpaper", "wood_wall", "spring", "summer", "autumn", "winter"]

var _colors: Dictionary[Color, Color] = {}
var _items: Array[Dictionary] = []
var _errors: int = 0


func _init() -> void:
	var furniture: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "furniture.png"))
	var structures: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "structures.png"))
	var portraits: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "portraits.png"))
	var tiles: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "tiles.png"))
	if furniture == null or structures == null or portraits == null or tiles == null:
		quit(1)
		return
	for index: int in FURNITURE.size():
		_save(_fit(Utils.extract(furniture, index % 4, index / 4, 4, 6, "object"), Vector2i(32, 32), Vector2i(28, 28)), "furniture/" + FURNITURE[index])
	var bounds: Array[Vector2i] = [Vector2i(64, 68), Vector2i(44, 44), Vector2i(68, 64), Vector2i(84, 70)]
	for index: int in STRUCTURES.size():
		var frame: Image = Utils.extract(structures, index % 3, index / 3, 3, 3, "object")
		if index < 4:
			_save(_fit(frame, Vector2i(96, 96), bounds[index]), "structures/" + STRUCTURES[index])
		else:
			_save(_fit(frame, Vector2i(32, 32), Vector2i(26, 28), 0.09), "objects/" + STRUCTURES[index])
	for row: int in 3:
		for column: int in 4:
			_save(_fit(Utils.extract(portraits, column, row, 4, 3, "object"), Vector2i(48, 48), Vector2i(44, 44)), "portraits/%s_%s" % [PEOPLE[column], EMOTIONS[row]])
	for index: int in TILES.size():
		var tile: Image = Utils.extract(tiles, index % 4, index / 4, 4, 2, "background")
		tile.resize(16, 16, Image.INTERPOLATE_NEAREST)
		_quantize_tile(tile, TILES[index])
		_save(tile, "tiles/" + TILES[index])
	var file: FileAccess = FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"source": SOURCE, "generator": "built-in image_gen", "preparation": "tools/art/prepare_presentation_art.gd", "sprites": _items}, "\t") + "\n")
	print("[presentation_art] %d sprites, %d errors" % [_items.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _fit(source: Image, canvas_size: Vector2i, extent: Vector2i, common_factor: float = -1.0) -> Image:
	var result: Image = Utils.canvas(canvas_size)
	var rect: Rect2i = source.get_used_rect()
	if rect.size == Vector2i.ZERO: return result
	var frame: Image = source.get_region(rect)
	var factor: float = minf(float(extent.x) / rect.size.x, float(extent.y) / rect.size.y)
	if common_factor > 0.0: factor = minf(factor, common_factor)
	frame.resize(maxi(1, roundi(rect.size.x * factor)), maxi(1, roundi(rect.size.y * factor)), Image.INTERPOLATE_NEAREST)
	result.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((canvas_size.x - frame.get_width()) / 2, canvas_size.y - frame.get_height() - 1))
	_quantize(result)
	return result


func _quantize(frame: Image) -> void:
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			if color.a < 0.5:
				frame.set_pixel(x, y, Color.TRANSPARENT)
				continue
			color.a = 1.0
			if not _colors.has(color):
				var nearest: Color = Style.PALETTE[0]
				var distance: float = INF
				for candidate: Color in Style.PALETTE:
					var delta: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
					if delta.length_squared() < distance:
						distance = delta.length_squared()
						nearest = candidate
				_colors[color] = nearest
			frame.set_pixel(x, y, _colors[color])


func _quantize_tile(frame: Image, name: String) -> void:
	var palette: Array[Color] = [Color("d3b491"), Color("e5c49f"), Color("efcfab"), Color("c9a47d")]
	if name == "wallpaper": palette = [Color("f0e6cd"), Color("e7dfc4"), Color("c7d1aa")]
	elif name == "wood_wall": palette = [Color("d3b38a"), Color("c0a17c"), Color("eee3c9")]
	elif name in ["spring", "summer"]: palette = [Color("b9ce83"), Color("c8d994"), Color("acc17b"), Color("dae4a8")]
	elif name == "autumn": palette = [Color("d8c28c"), Color("e5d3a2"), Color("bcad79"), Color("c69b78")]
	elif name == "winter": palette = [Color("eef1eb"), Color("e4edf0"), Color("cbdce3")]
	for y: int in frame.get_height():
		for x: int in frame.get_width():
			var color: Color = frame.get_pixel(x, y)
			var best: Color = palette[0]
			var distance: float = INF
			for candidate: Color in palette:
				var delta: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
				if delta.length_squared() < distance:
					distance = delta.length_squared()
					best = candidate
			frame.set_pixel(x, y, best)


func _save(frame: Image, name: String) -> void:
	var path: String = ROOT + name + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if frame.get_used_rect().size == Vector2i.ZERO or frame.save_png(path) != OK:
		_errors += 1
		push_error("[presentation_art] invalid output: " + path)
	_items.append({"path": name + ".png", "size": [frame.get_width(), frame.get_height()]})
