extends "res://scripts/ui/common/modal_panel.gd"
## View只报告摆放意图；世界选点由输入适配调用Presenter.set_target。

signal type_selected(type_id: StringName)
signal rotate_requested
signal commit_requested
signal dismantle_requested
signal retry_save_requested
signal closed
var _title: Label
var _reason: Label
var _catalog: OptionButton
var _commit: Button
var _dismantle: Button
var _retry: Button
var _types: Array[StringName] = []
var _rendering: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pauses_world = true
	theme = preload("res://assets/ui/farm_hud.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 右侧窄面板，保留地图供鼠标选择落点。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	frame.offset_left = -160
	frame.offset_right = -4
	frame.offset_top = -88
	frame.offset_bottom = 88
	add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	_title = Label.new()
	column.add_child(_title)
	_catalog = OptionButton.new()
	_catalog.item_selected.connect(_selected)
	column.add_child(_catalog)
	_reason = Label.new()
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(148, 36)
	column.add_child(_reason)
	column.add_child(_button("转向", func() -> void: rotate_requested.emit()))
	_commit = _button("确认摆放", func() -> void: commit_requested.emit())
	column.add_child(_commit)
	_dismantle = _button("拆回背包", func() -> void: dismantle_requested.emit())
	column.add_child(_dismantle)
	_retry = _button("重试保存", func() -> void: retry_save_requested.emit())
	column.add_child(_retry)
	column.add_child(_button("取消 [Esc]", set_open.bind(false)))
	hide()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func set_open(value: bool) -> void:
	var was_open: bool = visible
	_set_modal_open(value)
	if was_open and not visible: closed.emit()


func render(snapshot: Dictionary) -> void:
	if _title == null: return
	_rendering = true
	_title.text = "移动设备" if snapshot.get("moving", false) else "摆放设备"
	_catalog.clear()
	_types.clear()
	for entry: Dictionary in snapshot.get("catalog", []):
		_types.append(entry.id)
		_catalog.add_item(entry.title)
		if entry.id == snapshot.get("type_id"): _catalog.select(_types.size() - 1)
	_catalog.disabled = snapshot.get("moving", false)
	var cell: Vector2i = snapshot.get("cell", Vector2i.ZERO)
	_reason.text = "格子 %d,%d · 朝向 %d\n%s" % [cell.x, cell.y, int(snapshot.get("facing", 0)) + 1, snapshot.get("reason", "")]
	_commit.disabled = not snapshot.get("ok", false)
	_commit.text = "确认移动" if snapshot.get("moving", false) else "确认摆放"
	_dismantle.visible = snapshot.get("moving", false)
	_retry.visible = snapshot.get("save_pending", false)
	if snapshot.get("save_pending", false): _reason.text += "\n进度尚未保存，请重试"
	_rendering = false


func _selected(index: int) -> void:
	if not _rendering and index >= 0 and index < _types.size(): type_selected.emit(_types[index])


func _input(event: InputEvent) -> void:
	if visible and not event.is_echo() and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
