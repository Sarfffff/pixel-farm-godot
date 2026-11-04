extends Sprite2D
signal obstacle_changed
## 命中摇晃、木屑、最终倒下。倒下的树桩保留脚底碰撞，还能再用斧头清掉。

@export var hits_required: int = 3
## 树桩需要几下斧头才能连根清掉。
@export var stump_hits_required: int = 1
@export var persistent_id: StringName = &""

var hits_remaining: int
var is_felled: bool = false
var stump_hits_remaining: int
var _motion: Tween


func _ready() -> void:
	hits_remaining = hits_required
	stump_hits_remaining = stump_hits_required
	add_to_group(&"choppable")


func chop(direction: Vector2i) -> void:
	if is_felled:
		_chop_stump(direction)
		return
	hits_remaining -= 1
	if _motion != null and _motion.is_valid():
		_motion.kill()
	var side: float = -1.0 if direction.x < 0 else 1.0
	_motion = create_tween()
	if hits_remaining > 0:
		_motion.tween_property(self, "rotation", side * 0.10, 0.05)
		_motion.tween_property(self, "rotation", -side * 0.06, 0.07)
		_motion.tween_property(self, "rotation", 0.0, 0.10)
	else:
		is_felled = true
		# Y 排序节点不移动；绕脚底转动树冠。
		_motion.tween_property(self, "rotation", -side * 0.08, 0.08)
		_motion.tween_property(self, "rotation", side * 1.45, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_motion.tween_callback(_leave_stump)


## 砍树桩：先晃两下，最后一击连根拔起。
func _chop_stump(direction: Vector2i) -> void:
	if stump_hits_remaining <= 0 or get_meta(&"cleared", false):
		return
	stump_hits_remaining -= 1
	if _motion != null and _motion.is_valid():
		_motion.kill()
	var side: float = -1.0 if direction.x < 0 else 1.0
	_motion = create_tween()
	if stump_hits_remaining > 0:
		_motion.tween_property(self, "offset:x", side * 1.0, 0.05)
		_motion.tween_property(self, "offset:x", 0.0, 0.08)
	else:
		_motion.tween_property(self, "scale", Vector2(1.15, 0.85), 0.08)
		_motion.tween_property(self, "modulate:a", 0.0, 0.14)
		_motion.tween_callback(_clear_stump)


func _leave_stump(drop_wood: bool = true) -> void:
	rotation = 0.0
	# 使用同一图集中已有的树桩，避免裁切树根成为一条平面色块。
	region_rect = Rect2(48 if hits_required == 2 else 64, 32, 16, 16)
	offset = Vector2(0, -8)
	var body := get_node_or_null("Body") as StaticBody2D
	if body != null:
		body.collision_layer = 1
		var collision := body.get_node("Trunk") as CollisionShape2D
		var shape := RectangleShape2D.new()
		shape.size = Vector2(8 if hits_required == 2 else 10, 6)
		collision.shape = shape
		collision.position = Vector2(0, -3)
	set_meta(&"felled", true)
	if drop_wood:
		_drop_wood(hits_required)
	_obstacle_changed()


## 树桩被清掉：撤掉碰撞、掉落一根木材，脚下恢复成可开垦的草地。
func _clear_stump() -> void:
	set_meta(&"cleared", true)
	stump_hits_remaining = 0
	var body := get_node_or_null("Body") as StaticBody2D
	if body != null:
		body.queue_free()
	_drop_wood(1)
	_obstacle_changed()
	queue_free()


func persistence_id() -> StringName:
	return persistent_id if persistent_id != &"" else StringName("farm/tree/%d/%d" % [roundi(position.x), roundi(position.y)])


func to_dict() -> Dictionary:
	return {&"hits": hits_remaining, &"felled": is_felled, &"stump_hits": stump_hits_remaining, &"cleared": bool(get_meta(&"cleared", false))}


func from_dict(state: Dictionary) -> void:
	if _motion != null and _motion.is_valid():
		_motion.kill()
	hits_remaining = clampi(int(state.get("hits", hits_required)), 0, hits_required)
	stump_hits_remaining = clampi(int(state.get("stump_hits", stump_hits_required)), 0, stump_hits_required)
	is_felled = bool(state.get("felled", false))
	if is_felled:
		_leave_stump(false)
	_obstacle_changed()


func _obstacle_changed() -> void:
	obstacle_changed.emit()


## 砍倒给一批木料、清桩再给一根，都直接进背包（背包满时记一条警告）。
func _drop_wood(count: int) -> void:
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	if inventory == null:
		return
	var overflow: int = inventory.add_item(&"wood", count)
	if overflow <= 0:
		return
	push_warning("[choppable_tree] 背包已满，%d 根木材没能放下" % overflow)
	# 只写警告玩家看不到，补一条飘字；树已经倒了，木材只能损失这一部分。
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message("背包已满 · %d 根木材没能带走" % overflow)
