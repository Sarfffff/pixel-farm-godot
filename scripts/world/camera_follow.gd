extends Camera2D
## 相机跟随：平滑跟随目标脚底位置，并把视野限制在地图边界内。
##
## 与 Unity Cinemachine 的 Body 阻尼 + Confiner2D 等价：
## position_smoothing 负责阻尼，limit_* 负责边界。

@export var target_path: NodePath
@export var world_bounds: Rect2 = Rect2(0.0, 0.0, 640.0, 480.0)
## 目标点相对脚底的偏移，避免角色贴屏幕下缘。
@export var focus_offset: Vector2 = Vector2(0.0, -10.0)
@export var default_zoom: float = 1.25
@export var min_zoom: float = 1.0
@export var max_zoom: float = 2.0
@export var zoom_step: float = 0.125
@export var look_ahead_distance: float = 10.0

signal zoom_changed(value: float)
const PREFERENCES: String = "user://display_preferences.cfg"

var _target: Node2D
var _look_ahead: Vector2 = Vector2.ZERO
var _desired_zoom: float = 1.25
var _zoom_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		push_warning("[camera_follow] 未找到跟随目标：%s" % target_path)

	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	_apply_bounds()
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCES) == OK:
		_desired_zoom = float(preferences.get_value("camera", "zoom", default_zoom))
	else:
		_desired_zoom = default_zoom
	set_view_zoom(_desired_zoom, true, false)
	get_viewport().size_changed.connect(_on_viewport_resized)

	if _target != null:
		global_position = _target.global_position + focus_offset
		reset_smoothing()


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	var direction := Vector2.ZERO
	if _target is CharacterBody2D:
		direction = (_target as CharacterBody2D).velocity.normalized()
	_look_ahead = _look_ahead.lerp(direction * look_ahead_distance, 1.0 - exp(-delta * 5.0))
	global_position = (_target.global_position + focus_offset + _look_ahead).round()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var mode: int = DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_HOME:
			set_view_zoom(default_zoom)
			get_viewport().set_input_as_handled()
			return
	if _target != null and _target.get("input_locked") == true:
		return
	var change: float = 0.0
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change = zoom_step
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change = -zoom_step
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			change = zoom_step
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			change = -zoom_step
	if change != 0.0:
		set_view_zoom(_desired_zoom + change)
		get_viewport().set_input_as_handled()


func minimum_view_zoom() -> float:
	var view: Vector2 = get_viewport_rect().size
	return maxf(min_zoom, maxf(view.x / world_bounds.size.x, view.y / world_bounds.size.y))


func set_view_zoom(value: float, immediate: bool = false, remember: bool = true) -> void:
	var minimum: float = minimum_view_zoom()
	_desired_zoom = clampf(value, minimum, maxf(max_zoom, minimum))
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if immediate:
		zoom = Vector2.ONE * _desired_zoom
	else:
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(self, "zoom", Vector2.ONE * _desired_zoom, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	zoom_changed.emit(_desired_zoom)
	if remember:
		var preferences := ConfigFile.new()
		preferences.set_value("camera", "zoom", _desired_zoom)
		preferences.save(PREFERENCES)


## 切换世界（进出房屋）时换边界，并让缩放按新地图重新适配。
func set_world_bounds(bounds: Rect2) -> void:
	world_bounds = bounds
	_apply_bounds()
	set_view_zoom(_desired_zoom, true, false)
	reset_smoothing()


func _on_viewport_resized() -> void:
	set_view_zoom(_desired_zoom, true, false)


func _apply_bounds() -> void:
	limit_left = int(world_bounds.position.x)
	limit_top = int(world_bounds.position.y)
	limit_right = int(world_bounds.end.x)
	limit_bottom = int(world_bounds.end.y)
