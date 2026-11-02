extends RefCounted
## 单格是 1px 切角方形；四邻连片、对角补内角。使用原素材色板。

const DIRT := preload("res://assets/game/tilesets/tilled_dirt_wide.png")
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1),
]


static func mask_for(cell: Vector2i, cells: Dictionary) -> int:
	var mask: int = 0
	for index in DIRECTIONS.size():
		if cells.has(cell + DIRECTIONS[index]):
			mask |= 1 << index
	return mask


static func make_atlas_image() -> Image:
	var original: Image = DIRT.get_image()
	var fill: Color = original.get_pixel(16, 16)
	var rim: Color = original.get_pixel(3, 8)
	var furrow: Color = rim.lerp(fill, 0.3)
	var atlas := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for mask in 256:
		var origin := Vector2i(mask % 16, mask / 16) * 16
		for y in 16:
			for x in 16:
				var qx: int = 0 if x < 8 else 1
				var qy: int = 0 if y < 8 else 1
				var dx: int = x if qx == 0 else 15 - x
				var dy: int = y if qy == 0 else 15 - y
				var horizontal: bool = (mask & (8 if qx == 0 else 2)) != 0
				var vertical: bool = (mask & (1 if qy == 0 else 4)) != 0
				var diagonal_bit: int = [[4, 5], [7, 6]][qy][qx]
				var color: Color = fill
				if (not horizontal and dx == 0) or (not vertical and dy == 0):
					continue
				if (not horizontal and dx == 1) or (not vertical and dy == 1):
					color = rim
				if not horizontal and not vertical:
					if dx + dy <= 2:
						continue
					if dx + dy == 3:
						color = rim
				if horizontal and vertical and (mask & (1 << diagonal_bit)) == 0:
					if dx + dy == 0:
						continue
					if dx + dy == 1:
						color = rim
				if (y == 5 or y == 10) and x >= 4 and x <= 11 and x != 8:
					color = furrow
				atlas.set_pixelv(origin + Vector2i(x, y), color)
	return atlas


static func make_tileset() -> TileSet:
	var source := TileSetAtlasSource.new()
	var path: String = "res://assets/generated/terrain/soil_dry_atlas.png"
	source.texture = load(path) as Texture2D if ResourceLoader.exists(path) else ImageTexture.create_from_image(make_atlas_image())
	source.texture_region_size = Vector2i(16, 16)
	for mask in 256:
		source.create_tile(Vector2i(mask % 16, mask / 16))
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(16, 16)
	tileset.add_source(source, 0)
	return tileset
