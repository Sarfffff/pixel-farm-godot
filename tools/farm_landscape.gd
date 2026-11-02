extends RefCounted
## 河流、池塘、岸线、桥和草坡共用同一份格子数据，避免画面与碰撞脱节。

const W: int = 40
const H: int = 30
const HORIZONTAL_BRIDGE: Rect2i = Rect2i(9, 15, 8, 2)
const VERTICAL_BRIDGE: Rect2i = Rect2i(21, 20, 2, 8)
const BLUFF: Rect2i = Rect2i(2, 5, 5, 5)
const NEIGHBORS: Array[Vector2i] = preload("res://tools/terrain_tiles.gd").NEIGHBORS


static func water_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	# 每段都重叠，形成从北边界流向东边界、经过东南池塘的连续水系。
	for rect: Rect2i in [
		Rect2i(9, 0, 4, 7), Rect2i(10, 6, 4, 7), Rect2i(11, 12, 4, 7),
		Rect2i(12, 18, 5, 3), Rect2i(14, 20, 8, 3), Rect2i(17, 22, 12, 3),
		Rect2i(26, 19, 7, 8), Rect2i(24, 21, 11, 4), Rect2i(25, 20, 9, 6),
		Rect2i(34, 22, 6, 4),
	]:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				cells[Vector2i(x, y)] = true
	return cells


static func on_bridge(cell: Vector2i) -> bool:
	return HORIZONTAL_BRIDGE.has_point(cell) or VERTICAL_BRIDGE.has_point(cell)


static func paint(farm: Node2D) -> void:
	var cells: Dictionary[Vector2i, bool] = water_cells()
	var ground: TileMapLayer = farm.get_node("Ground") as TileMapLayer
	var water: TileMapLayer = farm.get_node("Water") as TileMapLayer
	var shore: TileMapLayer = farm.get_node("Overlay") as TileMapLayer
	var collision: TileMapLayer = farm.get_node("WaterCollision") as TileMapLayer
	for y: int in H:
		for x: int in W:
			var cell: Vector2i = Vector2i(x, y)
			if cells.has(cell):
				ground.erase_cell(cell)
				water.set_cell(cell, 2, Vector2i.ZERO)
				if not on_bridge(cell):
					collision.set_cell(cell, 2, Vector2i.ZERO)
				continue
			var mask: int = 0
			for index: int in NEIGHBORS.size():
				if not cells.has(cell + NEIGHBORS[index]):
					mask |= 1 << index
			if mask != 255:
				# 陆地边缘使用原草地的外角/内角，下方垫水避免透明角露出草底。
				water.set_cell(cell, 2, Vector2i.ZERO)
				shore.set_cell(cell, 3, Vector2i(mask % 16, mask / 16))
	_paint_paths(farm.get_node("Paths") as TileMapLayer)
	_paint_bridges(farm)
	_paint_bluff(farm)


static func _paint_paths(paths: TileMapLayer) -> void:
	for x: int in range(5, 30):
		if x >= 9 and x <= 16:
			continue
		paths.set_cell(Vector2i(x, 16), 4, Vector2i(1 + (x % 3), 3))
	for y: int in range(10, 19):
		paths.set_cell(Vector2i(29, y), 4, Vector2i(0, y % 3))
	for y: int in range(17, 20):
		paths.set_cell(Vector2i(21, y), 4, Vector2i(0, y % 3))
	for x: int in range(22, 29):
		paths.set_cell(Vector2i(x, 28), 4, Vector2i(1 + (x % 3), 3))


static func _paint_bridges(farm: Node2D) -> void:
	var bridge: TileMapLayer = farm.get_node("Bridges") as TileMapLayer
	for y: int in range(HORIZONTAL_BRIDGE.position.y, HORIZONTAL_BRIDGE.end.y):
		for x: int in range(HORIZONTAL_BRIDGE.position.x, HORIZONTAL_BRIDGE.end.x):
			var column: int = 2 if x == HORIZONTAL_BRIDGE.position.x else 4 if x == HORIZONTAL_BRIDGE.end.x - 1 else 3
			bridge.set_cell(Vector2i(x, y), 6, Vector2i(column, y - HORIZONTAL_BRIDGE.position.y))
	for y: int in range(VERTICAL_BRIDGE.position.y, VERTICAL_BRIDGE.end.y):
		for x: int in range(VERTICAL_BRIDGE.position.x, VERTICAL_BRIDGE.end.x):
			var row: int = 0 if y == VERTICAL_BRIDGE.position.y else 2 if y == VERTICAL_BRIDGE.end.y - 1 else 1
			bridge.set_cell(Vector2i(x, y), 6, Vector2i(x - VERTICAL_BRIDGE.position.x, row))
	# 桥上水碰撞挖空后，用护栏防止玩家从侧面踏进河里。
	var rails: StaticBody2D = StaticBody2D.new()
	rails.name = "BridgeRails"
	farm.add_child(rails)
	rails.owner = farm
	var horizontal: Rect2 = Rect2(Vector2(HORIZONTAL_BRIDGE.position * 16), Vector2(HORIZONTAL_BRIDGE.size * 16))
	var vertical: Rect2 = Rect2(Vector2(VERTICAL_BRIDGE.position * 16), Vector2(VERTICAL_BRIDGE.size * 16))
	_add_rect(rails, farm, Rect2(horizontal.position, Vector2(horizontal.size.x, 2)))
	_add_rect(rails, farm, Rect2(Vector2(horizontal.position.x, horizontal.end.y - 2), Vector2(horizontal.size.x, 2)))
	_add_rect(rails, farm, Rect2(vertical.position, Vector2(2, vertical.size.y)))
	_add_rect(rails, farm, Rect2(Vector2(vertical.end.x - 2, vertical.position.y), Vector2(2, vertical.size.y)))


static func _paint_bluff(farm: Node2D) -> void:
	var hills: TileMapLayer = farm.get_node("Hills") as TileMapLayer
	for y: int in range(BLUFF.position.y, BLUFF.end.y):
		for x: int in range(BLUFF.position.x, BLUFF.end.x):
			var column: int = 0 if x == BLUFF.position.x else 2 if x == BLUFF.end.x - 1 else 1
			var row: int = 0 if y == BLUFF.position.y else 2 if y == BLUFF.end.y - 1 else 1
			hills.set_cell(Vector2i(x, y), 5, Vector2i(column, row))
	var cliff: StaticBody2D = StaticBody2D.new()
	cliff.name = "CliffCollision"
	farm.add_child(cliff)
	cliff.owner = farm
	_add_rect(cliff, farm, Rect2(Vector2(BLUFF.position * 16), Vector2(BLUFF.size * 16)))


static func _add_rect(body: StaticBody2D, farm: Node2D, rect: Rect2) -> void:
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size
	var collision: CollisionShape2D = CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)
	collision.owner = farm
