extends Node
## 开发输入适配：组合根提供环境策略与日期用例；不承担正式休息或保存。

var enabled: bool:
	get: return _enabled
var _enabled: bool = false
var _advance: Callable
var _can_run: Callable
var _busy: bool = false
var _last_frame: int = -1


static func allowed(editor_build: bool, production: bool, explicitly_requested: bool) -> bool:
	return editor_build and not production and explicitly_requested


func configure(allow_tools: bool, advance: Callable, can_run: Callable) -> void:
	_enabled = allow_tools
	_advance = advance
	_can_run = can_run


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed(&"next_day") and request_advance():
		get_viewport().set_input_as_handled()


func request_advance() -> bool:
	if not _enabled or _busy or not _advance.is_valid() or not _can_run.is_valid():
		return false
	if _last_frame == Engine.get_process_frames() or not bool(_can_run.call()):
		return false
	_busy = true
	_last_frame = Engine.get_process_frames()
	_advance.call()
	_busy = false
	return true


func _exit_tree() -> void:
	_enabled = false
	_advance = Callable()
	_can_run = Callable()
