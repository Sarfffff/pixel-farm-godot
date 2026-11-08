extends Node2D
## 稳定实例的表现与交互；不持有库存或保存服务。

signal interacted(id: String)
var instance_id: String = ""
var type_id: StringName = &""
var _definition: Resource
var _sprite: Sprite2D
var _body: StaticBody2D


func configure(definition: Resource, record: Dictionary, world_position: Vector2) -> void:
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
	return "[F] 打开储物箱" if _definition.storage_capacity > 0 else "[F] 整理木围栏 · 移动或拆除"


func interact(_cell: Vector2i) -> void:
	interacted.emit(instance_id)
