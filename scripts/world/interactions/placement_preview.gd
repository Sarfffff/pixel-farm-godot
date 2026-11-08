extends Node2D
## 只绘制Presenter提供的占地快照，不自行决定放置规则。

var _cells: Array[Vector2i] = []
var _allowed: bool = false
var _position: Callable


func configure(cell_to_world: Callable) -> void:
	_position = cell_to_world
	z_index = 200


func render(snapshot: Dictionary) -> void:
	_cells.clear()
	_cells.assign(snapshot.get("cells", []))
	_allowed = bool(snapshot.get("ok", false))
	queue_redraw()


func _draw() -> void:
	if not _position.is_valid(): return
	var color: Color = Color(0.55, 0.8, 0.48, 0.45) if _allowed else Color(0.85, 0.35, 0.3, 0.5)
	for cell: Vector2i in _cells:
		var rectangle := Rect2(to_local(_position.call(cell)) - Vector2(8, 8), Vector2(16, 16))
		draw_rect(rectangle, color)
		draw_rect(rectangle, Color(color, 0.9), false, 1.0)


func _exit_tree() -> void:
	_position = Callable()
