extends CharacterBody2D
## 工具动作由角色动画驱动；目标在起手时确定，命中帧只提交一次。

signal tool_changed(tool: StringName)
signal action_started(tool: StringName, cell: Vector2i)
signal use_requested(tool: StringName, cell: Vector2i)

const WALK_SPEED: float = 72.0
const ACCELERATION: float = 900.0
const FRICTION: float = 1100.0
const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe"]

@onready var _sprite: AnimatedSprite2D = %Sprite

var current_tool: StringName = TOOLS[0]
var is_acting: bool = false
var interaction: Node
var _facing: StringName = &"down"
var _action_tool: StringName
var _action_cell: Vector2i
var _impact_sent: bool = false


func _ready() -> void:
	_sprite.frame_changed.connect(_on_sprite_frame_changed)
	_sprite.animation_finished.connect(_on_sprite_animation_finished)


func _physics_process(delta: float) -> void:
	if is_acting:
		velocity = Vector2.ZERO
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
	if event.is_echo():
		return
	if event.is_action_pressed(&"tool_next"):
		_select_tool(TOOLS.find(current_tool) + 1)
	elif event.is_action_pressed(&"tool_prev"):
		_select_tool(TOOLS.find(current_tool) - 1)
	else:
		for index in TOOLS.size():
			if event.is_action_pressed(StringName("tool_%d" % (index + 1))):
				_select_tool(index)
				return
		if event.is_action_pressed(&"use_tool") or event.is_action_pressed(&"mouse_use"):
			_start_action()


func facing_vector() -> Vector2i:
	match _facing:
		&"up": return Vector2i.UP
		&"left": return Vector2i.LEFT
		&"right": return Vector2i.RIGHT
		_: return Vector2i.DOWN


func _select_tool(index: int) -> void:
	if is_acting:
		return
	var next_tool: StringName = TOOLS[posmod(index, TOOLS.size())]
	if next_tool != current_tool:
		current_tool = next_tool
		tool_changed.emit(current_tool)


func _start_action() -> void:
	if is_acting or not is_instance_valid(interaction):
		return
	var cell: Vector2i = interaction.target_cell()
	if not interaction.can_use(current_tool, cell):
		return
	_action_tool = current_tool
	_action_cell = cell
	_impact_sent = false
	is_acting = true
	velocity = Vector2.ZERO
	action_started.emit(_action_tool, _action_cell)
	_sprite.play(StringName("%s_%s" % [_action_tool, _facing]))


func _on_sprite_frame_changed() -> void:
	var impact_frame: int = 1 if _action_tool == &"watering_can" else 2
	if is_acting and _sprite.frame == impact_frame and not _impact_sent:
		_impact_sent = true
		use_requested.emit(_action_tool, _action_cell)


func _on_sprite_animation_finished() -> void:
	if is_acting:
		is_acting = false
		_update_animation(false)


func _resolve_facing(input_direction: Vector2) -> StringName:
	if absf(input_direction.x) >= absf(input_direction.y):
		return &"right" if input_direction.x > 0.0 else &"left"
	return &"down" if input_direction.y > 0.0 else &"up"


func _update_animation(is_moving: bool) -> void:
	var state: String = "walk" if is_moving else "idle"
	var next_animation := StringName("%s_%s" % [state, _facing])
	if _sprite.animation != next_animation:
		_sprite.play(next_animation)
