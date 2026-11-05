extends RefCounted
## 只查询地形：按整个世界矩形检查草地，不把脚底一格当成整株占地。

const BLOCKING_LAYERS: Array[String] = ["Water", "Paths", "Bridges", "Hills"]


static func is_clear(farm: Node2D, world_rect: Rect2) -> bool:
	var ground: TileMapLayer = farm.get_node_or_null("Ground") as TileMapLayer
	if ground == null or not _covers(ground, world_rect, true):
		return false
	for name: String in BLOCKING_LAYERS:
		var layer: TileMapLayer = farm.get_node_or_null(NodePath(name)) as TileMapLayer
		if layer != null and not _covers(layer, world_rect, false):
			return false
	return true


static func _covers(layer: TileMapLayer, area: Rect2, require_tile: bool) -> bool:
	var first: Vector2i = layer.local_to_map(layer.to_local(area.position))
	var last: Vector2i = layer.local_to_map(layer.to_local(area.end - Vector2(0.01, 0.01)))
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			if (layer.get_cell_source_id(Vector2i(x, y)) != -1) != require_tile:
				return false
	return true
