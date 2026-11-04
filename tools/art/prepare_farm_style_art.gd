extends SceneTree
## ImageGen 原图的技术切片：保留生长比例、统一色板、二值 Alpha，不重绘美术。

const ROOT: String = "res://assets/packs/farm_style_v2/"
const SOURCE: String = "res://art/sources/farm_style_v2/"
const Utils = preload("res://tools/lib/content_art_utils.gd")
const PALETTE: Array[Color] = [
	Color("6c535b"), Color("956a69"), Color("b88a79"), Color("d1ab87"),
	Color("e8c9a5"), Color("f8ecd0"), Color("e9c583"), Color("d9a970"),
	Color("7b8d68"), Color("9fb275"), Color("b8cd8b"), Color("d3dda4"),
	Color("607a6a"), Color("6e8c7b"), Color("8fab94"), Color("a9c6a4"),
	Color("c4d6b6"), Color("6e7ca2"), Color("8e9cc1"), Color("b6bfe0"),
	Color("806485"), Color("a588a8"), Color("c4a8c5"), Color("b77581"),
	Color("d8959e"), Color("edbcc0"), Color("c1776f"), Color("df9283"),
]
const STAGES: Array[String] = ["sprout", "young", "growing", "mature"]
const ITEMS: Array[String] = ["blueberry", "blackberry_variant", "wild_mushroom", "wild_flower",
	"blueberry_seeds", "potato_seeds", "potato", "pickled_tomato"]
const KINDS: Array[String] = ["blackberry", "raspberry", "gooseberry"]
const BUSH_STAGES: Array[String] = ["sprout", "bare", "ripe"]

var _entries: Array[Dictionary] = []
var _errors: int = 0
var _colors: Dictionary[Color, Color] = {}


func _init() -> void:
	var crops: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "crops_forage_v2.png"))
	var berries: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "wild_berries_v2.png"))
	if crops == null or berries == null:
		printerr("[farm_style] missing generated source sheets")
		quit(1)
		return
	var crop_atlas: Image = Utils.canvas(Vector2i(128, 128))
	var berry_atlas: Image = Utils.canvas(Vector2i(128, 128))
	for row: int in 4:
		for column: int in 4:
			var cell: Image = _cell(crops, column, row)
			var path: String = "crops/%s/%s.png" % ["blueberry" if row == 0 else "potato", STAGES[column]] if row < 2 else "items/" + ITEMS[(row - 2) * 4 + column] + ".png"
			var frame: Image = _prepare(cell, row < 2)
			_save(frame, path)
			_place(crop_atlas, frame, column, row)
	for row: int in 3:
		for column: int in 4:
			var cell: Image = _cell(berries, column, row)
			var path: String = "berries/%s/%s.png" % [KINDS[row], BUSH_STAGES[column]] if column < 3 else "items/wild_%s.png" % KINDS[row]
			var frame: Image = _prepare(cell, column < 3)
			_save(frame, path)
			_place(berry_atlas, frame, column, row)
	for column: int in 3:
		var frame: Image = _prepare(_cell(berries, column, 3), false)
		_save(frame, "items/wild_%s_seeds.png" % KINDS[column])
		_place(berry_atlas, frame, column, 3)
	crop_atlas.save_png(ROOT + "crops_atlas.png")
	berry_atlas.save_png(ROOT + "berries_atlas.png")
	var manifest: FileAccess = FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"generator": "built-in image_gen", "source": SOURCE,
		"preparation": "tools/art/prepare_farm_style_art.gd", "world_canvas": [32, 32],
		"root_pixel_y": 31, "icon_canvas": [16, 16], "alpha": "binary", "items": _entries}, "\t") + "\n")
	print("[farm_style] %d sprites, %d errors" % [_entries.size(), _errors])
	quit(0 if _errors == 0 else 1)


func _cell(source: Image, column: int, row: int) -> Image:
	return Utils.extract(source, column, row, 4, 4, "object")


func _prepare(cell: Image, grounded: bool) -> Image:
	var size: Vector2i = Vector2i(32, 32) if grounded else Vector2i(16, 16)
	var result: Image = Utils.canvas(size)
	if grounded:
		# 用整格缩放，保持幼苗明显小于成株，再平移根部到统一脚底。
		cell.resize(32, 32, Image.INTERPOLATE_NEAREST)
		var bounds: Rect2i = cell.get_used_rect()
		result.blit_rect(cell, bounds, Vector2i((32 - bounds.size.x) / 2, 31 - bounds.size.y))
	else:
		var bounds: Rect2i = cell.get_used_rect()
		if bounds.size != Vector2i.ZERO:
			var trimmed: Image = cell.get_region(bounds)
			var factor: float = 14.0 / maxi(bounds.size.x, bounds.size.y)
			trimmed.resize(maxi(1, roundi(bounds.size.x * factor)), maxi(1, roundi(bounds.size.y * factor)), Image.INTERPOLATE_NEAREST)
			result.blit_rect(trimmed, Rect2i(Vector2i.ZERO, trimmed.get_size()), (size - trimmed.get_size()) / 2)
	for y: int in size.y:
		for x: int in size.x:
			var color: Color = result.get_pixel(x, y)
			result.set_pixel(x, y, _nearest(Color(color, 1.0)) if color.a >= 0.5 else Color.TRANSPARENT)
	return result


func _nearest(color: Color) -> Color:
	if not _colors.has(color):
		var best: Color = PALETTE[0]
		var distance: float = INF
		for candidate: Color in PALETTE:
			var delta: Vector3 = Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
			if delta.length_squared() < distance:
				distance = delta.length_squared()
				best = candidate
		_colors[color] = best
	return _colors[color]


func _save(frame: Image, relative_path: String) -> void:
	var path: String = ROOT + relative_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if frame.get_used_rect().size == Vector2i.ZERO or frame.save_png(path) != OK:
		_errors += 1
		push_error("[farm_style] empty or unwritable sprite: " + path)
	_entries.append({"path": relative_path, "size": [frame.get_width(), frame.get_height()]})


func _place(atlas: Image, frame: Image, column: int, row: int) -> void:
	var offset: Vector2i = Vector2i(32, 32) - frame.get_size()
	atlas.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(column, row) * 32 + offset / 2)
