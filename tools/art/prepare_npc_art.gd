extends SceneTree

const SOURCE: String = "res://assets/generated/sources/npc_v1/Production_game_asset__a_preci_2026-11-03T08-32-40.png"
const OUTPUT: String = "res://assets/generated/characters/npcs_v1/"
const IDS: Array[String] = ["shopkeeper", "gardener", "carpenter", "fisherman"]
const NAMES: Array[String] = ["商店老板", "园艺师", "木匠", "渔夫"]
const DIRECTIONS: Array[String] = ["down", "up", "left", "right"]
const SOURCE_COLUMNS: Array[int] = [0, 1, 3, 2]
const FRAME_SIZE: int = 32
const SPRITE_HEIGHT: int = 18
const FEET: Vector2i = Vector2i(16, 24)
const PALETTE: Array[Color] = [
	Color("47334f"), Color("6d526f"), Color("fcebc0"), Color("faf2d6"),
	Color("e1cd9f"), Color("b99c83"), Color("936b49"), Color("644533"),
	Color("bb9259"), Color("b76d54"), Color("d99488"), Color("7f946b"),
	Color("556644"), Color("688f91"), Color("697c9d"), Color("454958"),
	Color("73798a"), Color("aab1ba"), Color("d8d8ce"),
]

var _errors: int = 0


func _init() -> void:
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if source == null:
		push_error("[npc_art] Missing source")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var atlas: Image = _canvas(Vector2i(128, 128))
	var entries: Array[Dictionary] = []
	for row: int in IDS.size():
		var sheet: Image = _canvas(Vector2i(128, 32))
		var views: Dictionary[String, String] = {}
		for column: int in DIRECTIONS.size():
			var cell_size: Vector2i = Vector2i(source.get_width() / 4, source.get_height() / 4)
			var cell: Image = source.get_region(Rect2i(Vector2i(SOURCE_COLUMNS[column], row) * cell_size, cell_size))
			var sprite: Image = _prepare(cell)
			var path: String = IDS[row] + "_" + DIRECTIONS[column] + ".png"
			_save(sprite, path)
			views[DIRECTIONS[column]] = OUTPUT + path
			sheet.blit_rect(sprite, Rect2i(0, 0, 32, 32), Vector2i(column * 32, 0))
			atlas.blit_rect(sprite, Rect2i(0, 0, 32, 32), Vector2i(column, row) * 32)
		_save(sheet, IDS[row] + "_directions.png")
		entries.append({"id": IDS[row], "display_name": NAMES[row], "frame_size": [32, 32],
			"feet": [16, 24], "directions": DIRECTIONS, "views": views,
			"sheet": OUTPUT + IDS[row] + "_directions.png",
			"scene": "res://scenes/npcs/" + IDS[row] + ".tscn"})
	_save(atlas, "npc_atlas.png")
	var preview: Image = _canvas(Vector2i(160, 160))
	preview.fill(Color("34413f"))
	for row: int in 4:
		for column: int in 4:
			preview.blend_rect(atlas, Rect2i(Vector2i(column, row) * 32, Vector2i(32, 32)), Vector2i(column, row) * 40 + Vector2i(4, 4))
	preview.resize(960, 960, Image.INTERPOLATE_NEAREST)
	_save(preview, "npc_preview.png")
	var file: FileAccess = FileAccess.open(OUTPUT + "catalog.json", FileAccess.WRITE)
	if file == null:
		_errors += 1
		push_error("[npc_art] Cannot write catalog")
	else:
		file.store_string(JSON.stringify({"version": 1, "source": SOURCE,
			"generator": "image_gen; tools/art/prepare_npc_art.gd",
			"filter": "nearest", "alpha": "binary", "palette": "19 warm muted colors",
			"status": "Four directional idle poses only; no walk cycles or new profession gameplay",
			"scene_frame_order": DIRECTIONS, "items": entries}, "\t") + "\n")
	print("[npc_art] 4 characters, 16 directional poses, %d errors" % _errors)
	quit(0 if _errors == 0 else 1)


func _canvas(size: Vector2i) -> Image:
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _prepare(cell: Image) -> Image:
	cell.convert(Image.FORMAT_RGBA8)
	for y: int in cell.get_height():
		for x: int in cell.get_width():
			var color: Color = cell.get_pixel(x, y)
			var background: bool = color.r > 0.65 and color.b > 0.6 and color.g < 0.4
			cell.set_pixel(x, y, Color.TRANSPARENT if background or color.a < 0.5 else Color(color.r, color.g, color.b, 1.0))
	var bounds: Rect2i = cell.get_used_rect()
	var result: Image = _canvas(Vector2i(FRAME_SIZE, FRAME_SIZE))
	if bounds.size == Vector2i.ZERO:
		_errors += 1
		push_error("[npc_art] Empty pose")
		return result
	var crop: Image = cell.get_region(bounds)
	var width: int = clampi(roundi(float(bounds.size.x) * SPRITE_HEIGHT / bounds.size.y), 1, 24)
	crop.resize(width, SPRITE_HEIGHT, Image.INTERPOLATE_NEAREST)
	for y: int in crop.get_height():
		for x: int in crop.get_width():
			var color: Color = crop.get_pixel(x, y)
			if color.a >= 0.5:
				crop.set_pixel(x, y, _palette_color(color))
			else:
				crop.set_pixel(x, y, Color.TRANSPARENT)
	result.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i((FRAME_SIZE - width) / 2, FEET.y - SPRITE_HEIGHT))
	return result


func _palette_color(color: Color) -> Color:
	var nearest: Color = PALETTE[0]
	var distance: float = INF
	for candidate: Color in PALETTE:
		var difference: float = pow(color.r - candidate.r, 2) + pow(color.g - candidate.g, 2) + pow(color.b - candidate.b, 2)
		if difference < distance:
			distance = difference
			nearest = candidate
	return nearest


func _save(image: Image, name: String) -> void:
	if image.save_png(OUTPUT + name) != OK:
		_errors += 1
		push_error("[npc_art] Cannot save " + name)
