extends CharacterBody2D
## 鸡：在自己窝附近随机踱步，走到目标点就停一会儿，撞到东西立刻换方向。
##
## 素材只有左右两套帧（4 列 2 行：待机 / 走路各两帧），所以上下移动时保持当前朝向。
## 用 CharacterBody2D + move_and_slide，鸡会自己绕开树、窝和房子，不需要额外的寻路。

const SPEED: float = 16.0
const IDLE_MIN: float = 0.8
const IDLE_MAX: float = 2.4
## 换帧间隔，鸡走得慢，帧率给低一点像在啄食踱步。
const WALK_FRAME_TIME: float = 0.24

## 游走半径：以出生点为圆心，纵向幅度按 0.6 压缩，免得鸡跑到很远。
@export var home_radius: float = 40.0

@onready var _sprite: Sprite2D = $Sprite

var _home: Vector2
var _target: Vector2
var _wait: float = 0.0
var _facing_right: bool = true
var _walk_timer: float = 0.0
var _walk_phase: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"chicken")
	_home = global_position
	_rng.randomize()
	_pick_target()
	_show_idle_frame()


func _physics_process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		velocity = Vector2.ZERO
		_show_idle_frame()
		return

	var to_target: Vector2 = _target - global_position
	if to_target.length() < 4.0:
		_wait = _rng.randf_range(IDLE_MIN, IDLE_MAX)
		velocity = Vector2.ZERO
		_show_idle_frame()
		return

	velocity = to_target.normalized() * SPEED
	if absf(velocity.x) > 0.5:
		_facing_right = velocity.x > 0.0
	move_and_slide()
	if get_slide_collision_count() > 0:
		# 撞到树/窝/房子：重新选点，避免贴着障碍物来回抖。
		_pick_target()
		return

	_walk_timer += delta
	if _walk_timer >= WALK_FRAME_TIME:
		_walk_timer = 0.0
		_walk_phase = 1 - _walk_phase
	_show_walk_frame()


func _pick_target() -> void:
	for attempt in 3:
		var offset := Vector2(
			_rng.randf_range(-home_radius, home_radius),
			_rng.randf_range(-home_radius * 0.6, home_radius * 0.6)
		)
		if offset.length() > 8.0:
			_target = _home + offset
			return
	_target = _home


## 第 0 行：右待机 0 / 左待机 1。
func _show_idle_frame() -> void:
	_sprite.frame = 0 if _facing_right else 1


## 第 1 行：右走 4/6，左走 5/7。
func _show_walk_frame() -> void:
	_sprite.frame = (4 if _facing_right else 5) + _walk_phase * 2
