extends RefCounted
## 只拼接原素材的 8×8 象限，不重绘或缩放像素；256 邻域覆盖凹角与窄岸。

const SHORE_PATH: String = "res://assets/textures/terrain/river_shore_atlas.png"
const BRIDGE_PATH: String = "res://assets/textures/terrain/river_bridge_atlas_v2.png"
const PATH_PATH: String = "res://assets/textures/terrain/farm_path_atlas.png"
const NEIGHBORS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1),
]


static func make_shore_image() -> Image:
	var grass: Image = load("res://assets/textures/base/tilesets/grass.png").get_image()
	var atlas: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for mask: int in 256:
		var origin: Vector2i = Vector2i(mask % 16, mask / 16) * 16
		for qy: int in 2:
			for qx: int in 2:
				var horizontal: bool = (mask & (8 if qx == 0 else 2)) != 0
				var vertical: bool = (mask & (1 if qy == 0 else 4)) != 0
				var diagonal_bit: int = [[4, 5], [7, 6]][qy][qx]
				var tile: Vector2i = Vector2i(1 if horizontal else qx * 2, 1 if vertical else qy * 2)
				if horizontal and vertical and (mask & (1 << diagonal_bit)) == 0:
					tile = Vector2i(5 - qx, 2 - qy)
				var quadrant: Vector2i = Vector2i(qx, qy) * 8
				atlas.blit_rect(grass, Rect2i(tile * 16 + quadrant, Vector2i(8, 8)), origin + quadrant)
	return atlas


static func make_bridge_image() -> Image:
	var original: Image = load("res://assets/textures/base/objects/wood_bridge.png").get_image()
	var atlas: Image = Image.create(80, 48, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	# 原图的每行/列是独立的窄桥。保留两侧护栏，只重复内部木板来加宽。
	for y: int in 48:
		for x: int in 32:
			var sx: int = x if x < 4 else x - 16 if x >= 28 else 4 + (x - 4) % 8
			atlas.set_pixel(x, y, original.get_pixel(sx, y))
	for y: int in 32:
		for x: int in range(32, 80):
			var sy: int = y if y < 4 else y - 16 if y >= 28 else 4 + (y - 4) % 8
			atlas.set_pixel(x, y, original.get_pixel(x, sy))
	return atlas


static func make_tileset(base: TileSet) -> TileSet:
	var result: TileSet = base.duplicate(true) as TileSet
	for id: int in [2, 3, 4, 5, 6]:
		if result.has_source(id):
			result.remove_source(id)
	var water: TileSetAtlasSource = TileSetAtlasSource.new()
	water.texture = load("res://assets/textures/base/tilesets/water.png") as Texture2D
	water.create_tile(Vector2i.ZERO)
	water.set_tile_animation_columns(Vector2i.ZERO, 4)
	water.set_tile_animation_frames_count(Vector2i.ZERO, 4)
	water.set_tile_animation_speed(Vector2i.ZERO, 4.0)
	result.add_source(water, 2)
	var data: TileData = water.get_tile_data(Vector2i.ZERO, 0)
	data.set_collision_polygons_count(0, 1)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	]))
	_add_atlas(result, 3, SHORE_PATH)
	_add_atlas(result, 4, PATH_PATH)
	_add_atlas(result, 5, "res://assets/textures/base/tilesets/hills.png")
	_add_atlas(result, 6, BRIDGE_PATH)
	return result


static func _add_atlas(tileset: TileSet, id: int, path: String) -> void:
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = load(path) as Texture2D
	var size: Vector2i = source.texture.get_size() / 16
	for y: int in size.y:
		for x: int in size.x:
			source.create_tile(Vector2i(x, y))
	tileset.add_source(source, id)
