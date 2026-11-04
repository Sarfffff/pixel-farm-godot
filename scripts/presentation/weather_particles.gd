extends Node2D
## 像素雨丝、落地水花、飘雪和落叶；仅影响画面，不结算天气或日期。

var clock: Node
var weather: Node
var _age: float = 0.0
var _redraw_age: float = 0.0
var _water: Array[Vector2i] = []


func configure(time: Node, sky: Node, water: TileMapLayer) -> void:
	clock = time
	weather = sky
	_water.assign(water.get_used_cells())


func _process(delta: float) -> void:
	_age += delta
	_redraw_age += delta
	if _redraw_age >= 0.05:
		_redraw_age = 0.0
		queue_redraw()


func _draw() -> void:
	if clock == null: return
	var season: StringName = clock.season()
	if weather.is_rainy() and season != &"winter":
		for index: int in 100:
			var p: Vector2 = Vector2(fposmod(index * 83.0 - _age * 25.0, 640), fposmod(index * 47.0 + _age * 145.0, 480)).floor()
			draw_line(p, p + Vector2(-2, 5), Color(0.84, 0.91, 0.94, 0.58), 1.0, false)
		for index: int in 24:
			var p: Vector2 = Vector2(index * 79 % 624 + 8, index * 53 % 464 + 8)
			var phase: float = fposmod(_age * 2.0 + index * 0.23, 1.0)
			if phase < 0.4:
				draw_line(p + Vector2(-2, 0), p + Vector2(2, 0), Color(0.83, 0.91, 0.92, 0.65 - phase), 1.0, false)
	elif season == &"winter":
		for index: int in 45:
			var p: Vector2 = Vector2(fposmod(index * 71.0 + sin(_age + index) * 5, 640), fposmod(index * 67.0 + _age * 18.0, 480)).floor()
			draw_rect(Rect2(p, Vector2.ONE * (2 if index % 4 == 0 else 1)), Color(0.98, 0.98, 0.95, 0.8))
	elif season == &"autumn":
		for index: int in 15:
			var p: Vector2 = Vector2(fposmod(index * 113.0 + sin(_age + index) * 8, 640), fposmod(index * 47.0 + _age * 10.0, 480)).floor()
			draw_rect(Rect2(p, Vector2(2, 1)), Color("ce9d75") if index % 2 == 0 else Color("e2c788"))
	# 水面保持轻微动态，太阳下也不会像一张静止底图。
	if season != &"winter" and not _water.is_empty():
		for index: int in 12:
			var cell: Vector2i = _water[(index * 37) % _water.size()]
			var phase: float = fposmod(_age * 0.7 + index * 0.31, 1.0)
			if phase < 0.6:
				var p: Vector2 = Vector2(cell * 16) + Vector2(8, 8)
				var width: float = 2.0 + floorf(phase * 5.0)
				draw_line(p - Vector2(width, 0), p + Vector2(width, 0), Color(0.85, 0.95, 0.90, 0.45 - phase * 0.5), 1.0, false)
