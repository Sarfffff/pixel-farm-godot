extends Sprite2D
## 命中摇晃、木屑、最终倒下。树桩保留与可见根部匹配的碰撞。

@export var hits_required: int = 3
var hits_remaining: int
var is_felled: bool = false
var _motion: Tween


func _ready() -> void:
	hits_remaining = hits_required
	add_to_group(&"choppable")


func chop(direction: Vector2i) -> void:
	if is_felled:
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


func _leave_stump() -> void:
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
