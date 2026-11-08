extends "res://scripts/ui/common/modal_panel.gd"
## 模态任务日志，与农场手记分离；无业务状态、服务查找或资源扣除。

signal selection_requested(id: StringName)
signal accept_requested(id: StringName)
signal deliver_requested(id: StringName)
signal track_requested(id: StringName)
signal untrack_requested
signal refresh_requested

const Detail := preload("res://scripts/ui/panels/quest_detail.gd")

## 组合根/项目后续注册，推荐 Q；保留原手记 J。本 View 不修改 InputMap。
@export var toggle_action: StringName = &"toggle_quest_log"

var _list: ItemList
var _detail: VBoxContainer
var _message: Label
var _frame: PanelContainer
var _details_scroll: ScrollContainer
var _rendered_id: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pauses_world = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Detail.make_theme()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.07, 0.06, 0.5)
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)
	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.offset_left = 24
	_frame.offset_right = -24
	_frame.offset_top = 32
	_frame.offset_bottom = -32
	add_child(_frame)
	var column := VBoxContainer.new()
	_frame.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = "任务日志 · 主线"
	title.add_theme_font_size_override("font_size", 11)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(close)
	heading.add_child(close_button)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	_list = ItemList.new()
	_list.name = "QuestList"
	_list.custom_minimum_size.x = 138
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	content.add_child(_list)
	var scroll := ScrollContainer.new()
	_details_scroll = scroll
	scroll.name = "DetailsScroll"
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_detail = Detail.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)
	_detail.accept_requested.connect(_request_accept)
	_detail.deliver_requested.connect(_request_deliver)
	_detail.track_requested.connect(_request_track)
	_detail.untrack_requested.connect(_request_untrack)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	hide()


func render(data: Dictionary) -> void:
	var selected: StringName = StringName(data.get("selected_id", ""))
	var scroll: float = _list.get_v_scroll_bar().value
	_list.clear()
	for row: Dictionary in data.get("rows", []):
		var index: int = _list.add_item(String(row.text))
		_list.set_item_metadata(index, StringName(row.id))
		_list.set_item_tooltip(index, String(row.text))
		if StringName(row.id) == selected: _list.select(index)
	_list.get_v_scroll_bar().value = scroll
	_detail.render(data.get("detail", {}))
	if selected != _rendered_id:
		_details_scroll.scroll_vertical = 0
		_rendered_id = selected
	_message.text = String(data.get("message", ""))
	_message.visible = not _message.text.is_empty()


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


func _on_selected(index: int) -> void:
	selection_requested.emit(StringName(_list.get_item_metadata(index)))


func _on_shade_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()


func _request_accept(id: StringName) -> void:
	accept_requested.emit(id)


func _request_deliver(id: StringName) -> void:
	deliver_requested.emit(id)


func _request_track(id: StringName) -> void:
	track_requested.emit(id)


func _request_untrack() -> void:
	untrack_requested.emit()
