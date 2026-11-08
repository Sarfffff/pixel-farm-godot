extends Node
## 模态生命周期唯一所有者。注册新面板即可扩展，不在玩家和快捷栏维护名称表。

var switching: bool = false
var opening_allowed: Callable
var _panels: Array[Control] = []
var _lock_input: Callable
var _show_toolbar: Callable
var _owns_pause: bool = false
var _previous_pause: bool = false
var _previous_focus: WeakRef


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"modal_coordinator")


func configure(lock_input: Callable, show_toolbar: Callable) -> void:
	_lock_input = lock_input
	_show_toolbar = show_toolbar


func register_panel(panel: Control) -> void:
	if _panels.has(panel):
		return
	_panels.append(panel)
	panel.modal_coordinator = self
	panel.add_to_group(&"modal_ui")
	panel.visibility_changed.connect(_sync)
	panel.tree_exiting.connect(unregister_panel.bind(panel))
	_sync()


func unregister_panel(panel: Control) -> void:
	_panels.erase(panel)
	_sync()


func set_panel_open(panel: Control, open: bool) -> void:
	if open and opening_allowed.is_valid() and not bool(opening_allowed.call()):
		return
	if switching:
		panel.visible = open
		return
	switching = true
	if open:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus != null and not panel.is_ancestor_of(focus):
			_previous_focus = weakref(focus)
		panel.show()
		for other: Control in _panels:
			if is_instance_valid(other) and other != panel and other.visible:
				other.set_open(false)
	else:
		panel.hide()
	switching = false
	_sync()
	if not open and not has_open_panel() and _previous_focus != null:
		var focus: Control = _previous_focus.get_ref() as Control
		if focus != null and focus.is_visible_in_tree():
			focus.grab_focus.call_deferred()
		_previous_focus = null


func has_open_panel() -> bool:
	return _panels.any(func(panel: Control) -> bool: return is_instance_valid(panel) and panel.visible)


func can_open_panel() -> bool:
	return not has_open_panel() and (not opening_allowed.is_valid() or bool(opening_allowed.call()))


func _sync() -> void:
	if switching or not is_inside_tree():
		return
	var need_pause: bool = _panels.any(func(panel: Control) -> bool: return is_instance_valid(panel) and panel.visible and panel.pauses_world)
	if need_pause and not _owns_pause:
		_previous_pause = get_tree().paused
		_owns_pause = true
		get_tree().paused = true
	elif not need_pause and _owns_pause:
		get_tree().paused = _previous_pause
		_owns_pause = false
	var locked: bool = has_open_panel()
	if _lock_input.is_valid():
		_lock_input.call(locked)
	if _show_toolbar.is_valid():
		_show_toolbar.call(not locked)
