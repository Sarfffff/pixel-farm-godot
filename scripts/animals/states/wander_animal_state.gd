extends "res://scripts/animals/states/animal_state.gd"

var _idle: int
var _graze: int


func _init(idle: int, graze: int) -> void:
	_idle = idle
	_graze = graze


func enter(context: RefCounted) -> void:
	context.choose_target()


func tick(context: RefCounted, delta: float, position: Vector2) -> void:
	var offset: Vector2 = context.target - position
	if offset.length() <= maxf(context.profile.arrival_distance, 0.1):
		context.transition_to(_graze if context.random_chance(context.profile.graze_chance) else _idle)
	elif delta > 0.0:
		context.desired_velocity = offset.normalized() * minf(maxf(context.profile.move_speed, 0.0), offset.length() / delta)
