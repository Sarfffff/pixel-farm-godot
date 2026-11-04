extends RefCounted
## 每日用例编排。步骤通过 Callable 注入，时钟不再依赖农田，顺序不依赖信号连接时机。

var _finish_steps: Array[Callable] = []
var _begin_steps: Array[Callable] = []
var _clock: Node
var _advancing: bool = false


func _init(clock: Node) -> void:
	_clock = clock


func on_finish_day(step: Callable) -> void:
	_finish_steps.append(step)


func on_begin_day(step: Callable) -> void:
	_begin_steps.append(step)


func advance() -> void:
	if _advancing:
		return
	_advancing = true
	for step: Callable in _finish_steps:
		step.call(_clock.day)
	var previous_season: StringName = _clock.season()
	_clock.advance_date()
	for step: Callable in _begin_steps:
		step.call(_clock.day)
	_clock.publish_new_day(previous_season)
	_advancing = false


func clear() -> void:
	_finish_steps.clear()
	_begin_steps.clear()
	_clock = null
