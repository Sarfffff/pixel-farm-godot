extends Node2D
## 摆放面板打开时的地图选点适配：鼠标所在格交给Presenter，不决定任何规则。
## 面板打开会暂停世界，因此本节点常驻处理。

var _active: Callable
var _to_cell: Callable
var _set_target: Callable
var _last: Vector2i
var _has_last: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(active: Callable, to_cell: Callable, set_target: Callable) -> void:
	_active = active
	_to_cell = to_cell
	_set_target = set_target


func _process(_delta: float) -> void:
	if not _active.is_valid() or not bool(_active.call()):
		_has_last = false
		return
	if not _to_cell.is_valid() or not _set_target.is_valid():
		return
	var cell: Vector2i = _to_cell.call(get_global_mouse_position())
	# 只在目标格变化时刷新，避免每帧重算预览与库存预演。
	if _has_last and cell == _last:
		return
	_last = cell
	_has_last = true
	_set_target.call(cell)


func clear() -> void:
	_active = Callable()
	_to_cell = Callable()
	_set_target = Callable()
	_has_last = false
