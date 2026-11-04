extends SceneTree
## 对内置 ImageGen 原图做技术整理：切片、最近邻、色板、二值Alpha与地形边缘。

const Layout = preload("res://scripts/world/maps/region_layout.gd")
const Catalog = preload("res://tools/lib/world_region_catalog.gd")
const Utils = preload("res://tools/lib/content_art_utils.gd")
const ROOT: String = "res://assets/packs/world_regions_v1/"
const SOURCE: String = "res://art/sources/world_regions_v1/"
const PALETTE: Array[Color] = [Color("d4dfa2"), Color("c1d284"), Color("b4c679"), Color("a2b36b"), Color("8e9f60"), Color("788950"), Color("657749"), Color("d9b78c"), Color("e8c99e"), Color("f3d9ac"), Color("caa075"), Color("b58b6b"), Color("a07a61"), Color("88675a"), Color("72564e"), Color("5e4946"), Color("c2bdb5"), Color("aba8a4"), Color("95969b"), Color("808792"), Color("697888"), Color("546677"), Color("435666"), Color("80bbae"), Color("67ad9e"), Color("519e95"), Color("3d8e8a"), Color("317b80"), Color("286b75"), Color("215c68"), Color("aa9c60"), Color("938852"), Color("7d754a"), Color("d7a3a9"), Color("bd8792"), Color("a46e7f"), Color("8e6576"), Color("f3e5bc"), Color("e9ca7c"), Color("c5b8d1"), Color("a6a1bf"), Color("8c8cae"), Color("687b6a"), Color("859d76"), Color("abc098"), Color("c2d4b1"), Color("d39174"), Color("b97d69")]
var _colors: Dictionary = {}
var _entries: Array[Dictionary] = []
var _tiles: Array[Image] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for folder: String in ["terrain", "resources"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + folder))
	var terrain: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "terrain_source.png"))
	var resources: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "resources_source.png"))
	var trees: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "trees_source.png"))
	if terrain == null or resources == null or trees == null:
		printerr("[world_art] missing generated source image")
		quit(1)
		return
	var atlas := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for index: int in 16:
		var tile: Image = _cell(terrain, index % 4, index / 4, 4, 4)
		tile.resize(16, 16, Image.INTERPOLATE_NEAREST)
		_ground_quantize(tile, index)
		_tiles.append(tile)
		_save(tile, "terrain/" + Layout.TERRAIN_IDS[index] + ".png")
		atlas.blit_rect(tile, Rect2i(0, 0, 16, 16), Vector2i(index % 4, index / 4) * 16)
	_save(atlas, "terrain_atlas.png")
	var sprite_atlas := Image.create_empty(192, 128, false, Image.FORMAT_RGBA8)
	for index: int in 28:
		var frame: Image
		if index < 24:
			frame = _sprite(_cell(resources, index % 6, index / 6, 6, 4), 32)
			sprite_atlas.blit_rect(frame, Rect2i(0, 0, 32, 32), Vector2i(index % 6, index / 6) * 32)
		else:
			frame = _sprite(_cell(trees, (index - 24) % 2, (index - 24) / 2, 2, 2), 64)
		_save(frame, "resources/" + String(Catalog.RESOURCES[index][0]) + ".png")
	_save(sprite_atlas, "resources_atlas.png")
	_make_transitions()
	var file := FileAccess.open(ROOT + "catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"generator": "built-in image_gen", "source": SOURCE, "preparation": "tools/art/prepare_world_region_art.gd", "tile_size": 16, "resource_count": 28, "terrain_count": 16, "alpha": "binary", "sprite_palette_size": PALETTE.size(), "ground_palette": "per-surface low-contrast palette", "entries": _entries}, "\t"))
	print("[world_art] prepared 16 terrain tiles, 28 resources and 4096 transition combinations")
	quit(0)


func _cell(source: Image, column: int, row: int, columns: int, rows: int) -> Image:
	var start := Vector2i(roundi(float(source.get_width() * column) / columns), roundi(float(source.get_height() * row) / rows))
	var end := Vector2i(roundi(float(source.get_width() * (column + 1)) / columns), roundi(float(source.get_height() * (row + 1)) / rows))
	var result: Image = source.get_region(Rect2i(start, end - start))
	result.convert(Image.FORMAT_RGBA8)
	return result


func _sprite(cell: Image, size: int) -> Image:
	cell.resize(size, size, Image.INTERPOLATE_NEAREST)
	_quantize(cell, false)
	Utils.remove_fragments(cell)
	var bounds: Rect2i = cell.get_used_rect()
	var frame := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	frame.blit_rect(cell, bounds, Vector2i((size - bounds.size.x) / 2, size - 1 - bounds.size.y))
	return frame


func _ground_quantize(image: Image, index: int) -> void:
	# 地表缩小色差，主角和资源保持更高对比，避免大面积重复纹理抢视觉。
	var palettes: Dictionary = {0: [Color("bacd81"), Color("b3c67a"), Color("c1d284")], 1: [Color("b7c97d"), Color("aec176"), Color("c1d284")], 2: [Color("b4c679"), Color("adbf73"), Color("bccb82")], 3: [Color("83965e"), Color("899c63"), Color("7d9058")], 14: [Color("938852"), Color("998f58"), Color("8c834e")]}
	if not palettes.has(index):
		_quantize(image, true)
		return
	for y: int in 16:
		for x: int in 16:
			var color: Color = image.get_pixel(x, y)
			var best: Color = palettes[index][0]
			var distance: float = INF
			for candidate: Color in palettes[index]:
				var delta := Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
				if delta.length_squared() < distance:
					distance = delta.length_squared()
					best = candidate
			image.set_pixel(x, y, best)


func _quantize(image: Image, opaque: bool) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color: Color = image.get_pixel(x, y)
			if not opaque and color.a < 0.5:
				image.set_pixel(x, y, Color.TRANSPARENT)
				continue
			color.a = 1.0
			if not _colors.has(color):
				var best: Color = PALETTE[0]
				var distance: float = INF
				for candidate: Color in PALETTE:
					var delta := Vector3(color.r - candidate.r, color.g - candidate.g, color.b - candidate.b)
					if delta.length_squared() < distance:
						distance = delta.length_squared()
						best = candidate
				_colors[color] = best
			image.set_pixel(x, y, _colors[color])


func _make_transitions() -> void:
	var atlas := Image.create_empty(1024, 1024, false, Image.FORMAT_RGBA8)
	for base: int in 16:
		for other: int in 16:
			for mask: int in 16:
				var tile: Image = _tiles[base].duplicate()
				for y: int in 16:
					for x: int in 16:
						# 交错2至3像素边缘，复用生成贴图像素，不新增手绘纹理。
						var width: int = 2 + ((x / 3 + y / 3) % 2)
						if ((mask & 1) != 0 and y < width) or ((mask & 2) != 0 and x >= 16 - width) or ((mask & 4) != 0 and y >= 16 - width) or ((mask & 8) != 0 and x < width):
							tile.set_pixel(x, y, _tiles[other].get_pixel(x, y))
				var index: int = (base * 16 + other) * 16 + mask
				atlas.blit_rect(tile, Rect2i(0, 0, 16, 16), Vector2i(index % 64, index / 64) * 16)
	_save(atlas, "transition_atlas.png")


func _save(image: Image, relative: String) -> void:
	var path: String = ROOT + relative
	if image.get_used_rect().size == Vector2i.ZERO or image.save_png(path) != OK:
		push_error("[world_art] empty or unwritable asset: " + path)
		quit(1)
	_entries.append({"path": relative, "size": [image.get_width(), image.get_height()]})
