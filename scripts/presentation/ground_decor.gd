extends Node2D
## 只增加门槛衔接；道路纹理由Paths层统一绘制并参与植物占地查询。

var paths: TileMapLayer
var season: int = 0


func configure(layer: TileMapLayer) -> void:
	paths = layer
	queue_redraw()


func _draw() -> void:
	var earth: Color = Color("cbb58b") if season != 3 else Color("d0d4c4")
	for point: Vector2 in [Vector2(472, 144), Vector2(488, 256), Vector2(568, 80)]:
		draw_rect(Rect2(point + Vector2(-12, 0), Vector2(24, 6)), Color("c7baa0"))
		draw_rect(Rect2(point + Vector2(-10, 6), Vector2(20, 3)), Color("ded0b0"))
	draw_rect(Rect2(468, 265, 32, 9), earth)
