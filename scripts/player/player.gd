extends CharacterBody2D
## 玩家角色：四向移动 + 行走动画 + 朝向记忆 + 工具切换 + 使用工具动作。
##
## 角色原点在脚底中心，AnimatedSprite2D 上移 8px 使贴图底边贴合原点，
## 以便与道具做 Y 轴排序（V0.3）。
##
## 工具状态由角色持有（V0.4）：地块逻辑在 Farm 的 Tiller 节点里，
## 它读取 current_tool 与 facing_vector()，并通过两个信号协作：
##   action_started(tool) —— 动作起手，Tiller 播工具挥动表现
##   use_requested        —— 动作命中帧，Tiller 才真正改地形
##
## 角色动作帧（basic_charakter_actions.png）尚未接入，当前用"前冲 + 缩放"
## 的临时表现，见 `_play_action_motion`。

signal tool_changed(tool: StringName)
signal action_started(tool: StringName)
signal use_requested

const WALK_SPEED: float = 72.0
const ACCELERATION: float = 900.0
const FRICTION: float = 1100.0
## 一次工具动作的总时长与命中延迟
const ACTION_DURATION: float = 0.34
const IMPACT_DELAY: float = 0.15

## 工具顺序与工具栏槽位一一对应
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds"]

@onready var _sprite: AnimatedSprite2D = %Sprite

var current_tool: StringName = TOOLS[0]
## 动作期间锁住移动，避免边挥工具边跑
var is_acting: bool = false

var _facing: StringName = &"down"
var _sprite_origin: Vector2


func _ready() -> void:
	_sprite_origin = _sprite.position


func _physics_process(delta: float) -> void:
	if is_acting:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_direction: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_up", &"move_down"
	)

	if input_direction != Vector2.ZERO:
		_facing = _resolve_facing(input_direction)
		velocity = velocity.move_toward(input_direction * WALK_SPEED, ACCELERATION * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

	move_and_slide()
	_update_animation(input_direction != Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tool_next"):
		_select_tool(TOOLS.find(current_tool) + 1)
	elif event.is_action_pressed(&"tool_prev"):
		_select_tool(TOOLS.find(current_tool) - 1)
	elif event.is_action_pressed(&"tool_1"):
		_select_tool(0)
	elif event.is_action_pressed(&"tool_2"):
		_select_tool(1)
	elif event.is_action_pressed(&"tool_3"):
		_select_tool(2)
	elif event.is_action_pressed(&"use_tool") or event.is_action_pressed(&"mouse_use"):
		_start_action()


## 当前朝向对应的格子方向，供交互系统计算"面前格"。
func facing_vector() -> Vector2i:
	match _facing:
		&"up":
			return Vector2i.UP
		&"left":
			return Vector2i.LEFT
		&"right":
			return Vector2i.RIGHT
		_:
			return Vector2i.DOWN


func _select_tool(index: int) -> void:
	if is_acting:
		return
	var wrapped: int = posmod(index, TOOLS.size())
	var next_tool: StringName = TOOLS[wrapped]
	if next_tool == current_tool:
		return
	current_tool = next_tool
	tool_changed.emit(current_tool)


## 起手 → 命中帧改地形 → 收手。动作期间禁止移动与切换工具。
func _start_action() -> void:
	if is_acting:
		return
	is_acting = true
	_update_animation(false)
	action_started.emit(current_tool)
	_play_action_motion()

	await get_tree().create_timer(IMPACT_DELAY).timeout
	use_requested.emit()

	await get_tree().create_timer(ACTION_DURATION - IMPACT_DELAY).timeout
	is_acting = false
	_update_animation(false)


## 临时动作表现：朝面向方向小幅前冲再回位。
## 等 basic_charakter_actions.png 的分帧确认后，替换为真正的动作动画。
func _play_action_motion() -> void:
	var offset: Vector2 = Vector2(facing_vector()) * 2.0
	var tween := create_tween()
	tween.tween_property(_sprite, "position", _sprite_origin + offset, 0.08)
	tween.tween_property(_sprite, "position", _sprite_origin, 0.2)


## 方向键同时按下时，取分量更大的轴作为朝向，避免斜向出现抖动切换。
func _resolve_facing(input_direction: Vector2) -> StringName:
	if absf(input_direction.x) >= absf(input_direction.y):
		return &"right" if input_direction.x > 0.0 else &"left"
	return &"down" if input_direction.y > 0.0 else &"up"


func _update_animation(is_moving: bool) -> void:
	var state: String = "walk" if is_moving else "idle"
	var next_animation := StringName("%s_%s" % [state, _facing])
	if _sprite.animation != next_animation:
		_sprite.play(next_animation)
