@tool
extends StaticBody2D
## 围栏按既有桥侧碰撞条绘制，桥长或位置变化时，画面与阻挡保持同源。

const FENCE: Texture2D = preload("res://assets/textures/base/tilesets/fences.png")
const POST: Rect2 = Rect2(5, 49, 6, 11)
const HORIZONTAL_BEAMS: Rect2 = Rect2(28, 52, 4, 6)
const VERTICAL_BEAM: Rect2 = Rect2(7, 12, 2, 4)
const POST_SPACING: float = 16.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _draw() -> void:
	for child: Node in get_children():
		var collider: CollisionShape2D = child as CollisionShape2D
		if collider == null or collider.disabled or not collider.shape is RectangleShape2D:
			continue
		var shape: RectangleShape2D = collider.shape as RectangleShape2D
		var horizontal: bool = shape.size.x > shape.size.y
		var axis: Vector2 = Vector2.RIGHT if horizontal else Vector2.DOWN
		var length: float = shape.size.x if horizontal else shape.size.y
		var start: Vector2 = collider.position - axis * (length / 2.0 - 2.0)
		var end: Vector2 = collider.position + axis * (length / 2.0 - 2.0)
		if horizontal:
			draw_texture_rect_region(FENCE, Rect2(start + Vector2(0, -7), Vector2(end.x - start.x, 6)), HORIZONTAL_BEAMS)
		else:
			draw_texture_rect_region(FENCE, Rect2(start + Vector2(-1, -6), Vector2(2, end.y - start.y)), VERTICAL_BEAM)
		var distance: float = 0.0
		while distance < length - 4.0:
			_draw_post(start + axis * distance)
			distance += POST_SPACING
		_draw_post(end)


func _draw_post(foot: Vector2) -> void:
	draw_texture_rect_region(FENCE, Rect2(foot + Vector2(-3, -10), POST.size), POST)
