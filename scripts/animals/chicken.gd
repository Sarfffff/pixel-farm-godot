extends "res://scripts/animals/farm_animal.gd"
## 小鸡适配自身的单向图集，行为由 FarmAnimal + AnimalStateMachine 共用。
## 上下移动时保持左右朝向；素材没有觅食/睡眠专用帧，停留行为沿用站姿。

const WALK_FRAME_TIME: float = 0.24
## 0为站姿、1为眨眼，2/3为空格；4至7是同一朝向的完整四步，左行须镜像。
const WALK_FIRST: int = 4
const WALK_FRAME_COUNT: int = 4

var _facing_right: bool = true
var _walk_timer: float = 0.0
var _walk_phase: int = 0


func _ready() -> void:
	add_to_group(&"chicken")
	super._ready()


func _update_facing(direction: Vector2) -> void:
	super._update_facing(direction)
	if not is_zero_approx(direction.x):
		_facing_right = direction.x > 0.0


func _update_visual(delta: float, moving: bool) -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	sprite.flip_h = not _facing_right
	if not moving:
		_walk_timer = 0.0
		_walk_phase = 0
		sprite.frame = 0
		return
	_walk_timer += maxf(delta, 0.0)
	while _walk_timer >= WALK_FRAME_TIME:
		_walk_timer -= WALK_FRAME_TIME
		_walk_phase = (_walk_phase + 1) % WALK_FRAME_COUNT
	sprite.frame = WALK_FIRST + _walk_phase
