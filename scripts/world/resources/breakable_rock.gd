extends Sprite2D

signal struck(hits_left: int)
signal broken
signal obstacle_changed

const RockConfig = preload("res://scripts/data/rock_data.gd")
const DEFAULT_DATA: RockConfig = preload("res://data/rocks/field_rock.tres")

@export var data: RockConfig = DEFAULT_DATA
@export var persistent_id: StringName = &""
@onready var _body: StaticBody2D = $Body
@onready var _collision: CollisionShape2D = $Body/Base

var hits_remaining: int = 0
var is_broken: bool = false
var _rest_offset: Vector2
var _motion: Tween


func _ready() -> void:
	hits_remaining = int(data.hits_required)
	_rest_offset = offset
	add_to_group(&"breakable_rock")
	queue_redraw()


func can_mine() -> bool:
	if is_broken or is_queued_for_deletion():
		return false
	if hits_remaining > 1:
		return true
	var inventory: Inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	return inventory != null and inventory.has_space_for(StringName(data.drop_item_id), int(data.drop_amount))


func mine(direction: Vector2i) -> bool:
	if not can_mine():
		if not is_broken:
			_show_full_bag()
		return false
	hits_remaining = maxi(0, hits_remaining - 1)
	_record_state()
	struck.emit(hits_remaining)
	if _motion != null and _motion.is_valid():
		_motion.kill()
	offset = _rest_offset
	queue_redraw()
	if hits_remaining == 0:
		var inventory: Inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
		inventory.add_item(StringName(data.drop_item_id), int(data.drop_amount))
		_clear_collision()
		broken.emit()
		_motion = create_tween()
		_motion.tween_property(self, "scale", Vector2(1.15, 0.72), 0.08)
		_motion.tween_callback(hide)
		_motion.tween_interval(0.10)
		_motion.tween_callback(queue_free)
	else:
		_motion = create_tween()
		_motion.tween_property(self, "offset", _rest_offset + Vector2(direction) * 2.0, 0.035)
		_motion.tween_property(self, "offset", _rest_offset - Vector2(direction), 0.045)
		_motion.tween_property(self, "offset", _rest_offset, 0.075)
	return true


func _clear_collision() -> void:
	is_broken = true
	set_meta(&"felled", true)
	set_meta(&"cleared", true)
	remove_from_group(&"breakable_rock")
	_body.collision_layer = 0
	_body.collision_mask = 0
	_collision.set_deferred(&"disabled", true)
	obstacle_changed.emit()


func restore_state(hits: int) -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	hits_remaining = clampi(hits, 0, int(data.hits_required))
	offset = _rest_offset
	_record_state()
	if hits_remaining == 0:
		_clear_collision()
		hide()
		queue_free()
	else:
		queue_redraw()


func _record_state() -> void:
	var states: Dictionary = get_parent().get_meta(&"rock_states", {})
	states[String(persistence_id())] = hits_remaining
	get_parent().set_meta(&"rock_states", states)


func persistence_id() -> StringName:
	return persistent_id if persistent_id != &"" else StringName("farm/rock/%d/%d" % [roundi(position.x), roundi(position.y)])


func to_dict() -> Dictionary:
	return {&"hits": hits_remaining, &"cleared": is_broken}


func from_dict(state: Dictionary) -> void:
	restore_state(int(state.get("hits", data.hits_required)))


func _show_full_bag() -> void:
	var toast: Node = get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message("背包空间不足 · 腾出空间再敲最后一下")


func _draw() -> void:
	if hits_remaining <= 0 or hits_remaining >= int(data.hits_required):
		return
	var crack: Color = Color("47414d")
	var pivot: Vector2 = offset + Vector2(0, -1)
	draw_polyline(PackedVector2Array([pivot + Vector2(-5, -4), pivot + Vector2(-2, -1), pivot + Vector2(-4, 1), pivot + Vector2(-1, 5)]), crack, 1.0, false)
	if hits_remaining == 1:
		draw_polyline(PackedVector2Array([pivot + Vector2(-2, -1), pivot + Vector2(2, -3), pivot + Vector2(6, -1), pivot + Vector2(5, 3)]), crack, 1.0, false)
