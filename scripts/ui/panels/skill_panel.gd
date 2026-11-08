extends "res://scripts/ui/common/modal_panel.gd"
## 技能 View：只显示快照，选择行与开关属于界面意图，不接库存或劳动事件。

signal selection_requested(id: StringName)
signal refresh_requested

## 组合根可选择空闲键；默认只通过现有界面按钮或 Presenter.open() 打开。
@export var toggle_action: StringName = &""

var _list: ItemList
var _heading: Label
var _body: Label
var _frame: PanelContainer
var _scroll: ScrollContainer
var _rendered_id: StringName = &""


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	pauses_world = true
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = preload("res://scripts/ui/panels/quest_detail.gd").make_theme()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.07, 0.06, 0.5)
	shade.gui_input.connect(_shade_input)
	add_child(shade)
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_frame.offset_left = 24
	_frame.offset_right = -24
	_frame.offset_top = 32
	_frame.offset_bottom = -32
	add_child(_frame)
	var column := VBoxContainer.new()
	_frame.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = "技能 · 劳动与成长"
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var content := HBoxContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(content)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 108
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.item_selected.connect(_selected)
	content.add_child(_list)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	_scroll.add_child(detail)
	_heading = Label.new()
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heading.add_theme_font_size_override("font_size", 10)
	detail.add_child(_heading)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_body)
	hide()


func render(data: Dictionary) -> void:
	var selected: StringName = StringName(data.get("selected_id", ""))
	_list.clear()
	for row: Dictionary in data.get("rows", []):
		var index: int = _list.add_item(String(row.text))
		_list.set_item_metadata(index, StringName(row.id))
		if StringName(row.id) == selected: _list.select(index)
	var detail: Dictionary = data.get("detail", {})
	_heading.text = String(detail.get("title", "暂无技能"))
	_body.text = String(detail.get("text", ""))
	if selected != _rendered_id:
		_scroll.scroll_vertical = 0
		_rendered_id = selected


func open() -> void:
	_set_modal_open(true)
	if not visible: return
	refresh_requested.emit()
	_list.grab_focus()


func close() -> void:
	_set_modal_open(false)


func set_open(value: bool) -> void:
	if value: open()
	else: close()


func _input(event: InputEvent) -> void:
	if visible and not event.is_echo() and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo() or toggle_action == &"" or not InputMap.has_action(toggle_action): return
	if event.is_action_pressed(toggle_action) and (visible or _can_open_modal()):
		set_open(not visible)
		get_viewport().set_input_as_handled()


func _selected(index: int) -> void:
	selection_requested.emit(StringName(_list.get_item_metadata(index)))


func _shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()
