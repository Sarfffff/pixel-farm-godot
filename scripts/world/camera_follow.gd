extends Camera2D
## 相机跟随：平滑跟随目标脚底位置，并把视野限制在地图边界内。
##
## 与 Unity Cinemachine 的 Body 阻尼 + Confiner2D 等价：
## position_smoothing 负责阻尼，limit_* 负责边界。

@export var target_path: NodePath
@export var world_bounds: Rect2 = Rect2(0.0, 0.0, 640.0, 480.0)
## 目标点相对脚底的偏移，避免角色贴屏幕下缘。
@export var focus_offset: Vector2 = Vector2(0.0, -10.0)

var _target: Node2D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		push_warning("[camera_follow] 未找到跟随目标：%s" % target_path)

	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	_apply_bounds()

	if _target != null:
		global_position = _target.global_position + focus_offset
		reset_smoothing()


func _physics_process(_delta: float) -> void:
	if _target == null:
		return
	global_position = _target.global_position + focus_offset


func _apply_bounds() -> void:
	limit_left = int(world_bounds.position.x)
	limit_top = int(world_bounds.position.y)
	limit_right = int(world_bounds.end.x)
	limit_bottom = int(world_bounds.end.y)
