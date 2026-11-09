extends Node2D
## 稳定实例的表现与交互；不持有库存或保存服务。

signal interacted(id: String)
const VALID_PHASES: Array[StringName] = [&"idle", &"working", &"ready"]
var instance_id: String = ""
var type_id: StringName = &""
var _definition: Resource
var _sprite: Sprite2D
var _body: StaticBody2D
var _visual_phase: StringName = &"idle"
var _state_label: Label


func configure(definition: Resource, record: Dictionary, world_position: Vector2) -> void:
	clear_state()
	_definition = definition
	instance_id = record.id
	type_id = definition.id
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
		_body = StaticBody2D.new()
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		collision.shape = shape
		_body.add_child(collision)
		add_child(_body)
		add_to_group(&"interactable")
	_sprite.texture = definition.texture
	_sprite.scale = definition.visual_scale
	_sprite.position = Vector2(0, -6)
	_sprite.rotation = PI * 0.5 * int(record.facing) if definition.storage_capacity == 0 else 0.0
	var size: Vector2i = definition.footprint if int(record.facing) % 2 == 0 else Vector2i(definition.footprint.y, definition.footprint.x)
	var collider: CollisionShape2D = _body.get_child(0)
	(collider.shape as RectangleShape2D).size = Vector2(size) * 16.0 - Vector2(2, 2)
	_body.position = Vector2(size - Vector2i.ONE) * 8.0
	position = world_position


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 28.0


func hint() -> String:
	var base: String = "[F] 打开储物箱" if _definition.storage_capacity > 0 else "[F] 整理木围栏 · 移动或拆除"
	if _visual_phase == &"working": return base + " · 加工中"
	if _visual_phase == &"ready": return base + " · 可领取"
	return base


func interact(_cell: Vector2i) -> void:
	interacted.emit(instance_id)


## 只改表现：三态贴图、hint 与可选小标签；业务状态仍由外部加工服务持有。
func set_state(state: Dictionary) -> void:
	if _definition == null or _sprite == null: return
	_visual_phase = _normalize_phase(state.get("phase", &"idle"))
	_sprite.texture = _phase_texture(_visual_phase, state)
	_apply_label(String(state.get("label", "")))


## 释放或重建时清空表现状态；贴图回到 idle 原图，小标签立即移除。
func clear_state() -> void:
	_visual_phase = &"idle"
	_clear_label()
	if _sprite != null and is_instance_valid(_sprite) and _definition != null:
		_sprite.texture = _definition.texture


func _normalize_phase(value: Variant) -> StringName:
	if value is StringName and VALID_PHASES.has(value): return value
	if value is String and VALID_PHASES.has(StringName(value)): return StringName(value)
	return &"idle"


func _phase_texture(phase: StringName, state: Dictionary) -> Texture2D:
	if phase == &"idle": return _definition.texture
	var supplied: Variant = state.get("texture", null)
	if supplied is Texture2D: return supplied
	var authored: Variant = _definition.get(StringName("%s_texture" % phase))
	if authored is Texture2D: return authored
	return _definition.texture


func _apply_label(text: String) -> void:
	if text.is_empty():
		_clear_label()
		return
	if _state_label == null or not is_instance_valid(_state_label):
		_state_label = Label.new()
		_state_label.name = "StateLabel"
		_state_label.position = Vector2(-16, -26)
		add_child(_state_label)
	_state_label.text = text


func _clear_label() -> void:
	if _state_label != null and is_instance_valid(_state_label):
		remove_child(_state_label)
		_state_label.queue_free()
	_state_label = null


func _exit_tree() -> void:
	_visual_phase = &"idle"
	_state_label = null
