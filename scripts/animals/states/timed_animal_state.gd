extends "res://scripts/animals/states/animal_state.gd"
## 计时停留状态：待机和觅食共用，时长与下一状态在构造时指定。

var _minimum_key: StringName
var _maximum_key: StringName
var _next: int


func _init(minimum: StringName, maximum: StringName, next: int) -> void:
	_minimum_key = minimum
	_maximum_key = maximum
	_next = next


func enter(context: RefCounted) -> void:
	context.duration = context.sample_duration(context.profile.get(_minimum_key), context.profile.get(_maximum_key))


func tick(context: RefCounted, _delta: float, _position: Vector2) -> void:
	if context.elapsed >= context.duration:
		context.transition_to(_next)
