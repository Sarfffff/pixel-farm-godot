extends Node2D
## 只增加地面衔接，不写地图格子、不改碰撞与可种植区。

var paths: TileMapLayer
var season: int = 0
var _cells: Dictionary[Vector2i, bool] = {}


func configure(layer: TileMapLayer) -> void:
	paths = layer
	for cell: Vector2i in paths.get_used_cells(): _cells[cell] = true
	# 社区入口沿农舍东侧绕行，围栏中间留出门洞。
	for y: int in range(5, 10): _cells[Vector2i(35, y)] = true
	for x: int in range(32, 36): _cells[Vector2i(x, 9)] = true
	for y: int in range(9, 12): _cells[Vector2i(32, y)] = true
	for x: int in range(29, 33): _cells[Vector2i(x, 11)] = true
	queue_redraw()


func _draw() -> void:
	var earth: Color = Color("cbb58b") if season != 3 else Color("d0d4c4")
	var edge: Color = Color("bba17b") if season != 3 else Color("b8c6c8")
	for cell: Vector2i in _cells:
		var point: Vector2 = Vector2(cell * 16)
		if _cells.has(cell + Vector2i.LEFT) or _cells.has(cell + Vector2i.RIGHT):
			draw_rect(Rect2(point + Vector2(0, 2), Vector2(16, 12)), earth)
		if _cells.has(cell + Vector2i.UP) or _cells.has(cell + Vector2i.DOWN):
			draw_rect(Rect2(point + Vector2(2, 0), Vector2(12, 16)), earth)
		if (cell.x + cell.y) % 3 == 0:
			draw_rect(Rect2(point + Vector2(3, 3), Vector2(2, 1)), edge)
	for point: Vector2 in [Vector2(472, 144), Vector2(488, 256), Vector2(568, 80)]:
		draw_rect(Rect2(point + Vector2(-12, 0), Vector2(24, 6)), Color("c7baa0"))
		draw_rect(Rect2(point + Vector2(-10, 6), Vector2(20, 3)), Color("ded0b0"))
	draw_rect(Rect2(468, 265, 32, 9), earth)
