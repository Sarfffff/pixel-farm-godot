extends Node2D
## 硬边像素粒子。每次命中独立实例，连续动作不会截断上次效果。

var kind: StringName
var direction: Vector2
var _age: float = 0.0
var _particles: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _colors: Array[Color] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count: int = 14 if kind == &"watering_can" else 9
	for index in count:
		var water: bool = kind == &"watering_can"
		_particles.append(-direction * 8.0 + Vector2(0, -6) if water else Vector2.ZERO)
		_velocities.append(Vector2(rng.randf_range(-18, 18), rng.randf_range(-40, -18)))
		if water:
			_velocities[index] = direction * rng.randf_range(20, 35) + Vector2(rng.randf_range(-8, 8), -12)
		var palette: Array[Color] = [Color("b38b58"), Color("dbb980"), Color("90734c")]
		if water:
			palette = [Color("b8e1dc"), Color("88bdcb"), Color("e1eee0")]
		_colors.append(palette[index % palette.size()])


func _process(delta: float) -> void:
	_age += delta
	if _age > 0.42:
		queue_free()
		return
	for index in _particles.size():
		_velocities[index].y += 100.0 * delta
		_particles[index] += _velocities[index] * delta
	queue_redraw()


func _draw() -> void:
	for index in _particles.size():
		if _age < 0.25 + float(index % 4) * 0.04:
			draw_rect(Rect2(_particles[index].round(), Vector2(1, 2) if kind == &"watering_can" else Vector2.ONE), _colors[index])
	if kind == &"watering_can" and _age > 0.12 and _age < 0.33:
		var radius: float = 2.0 if _age < 0.23 else 4.0
		draw_line(Vector2(-radius, 1), Vector2(-1, 1), Color("88bdcb"))
		draw_line(Vector2(1, 1), Vector2(radius, 1), Color("b8e1dc"))
