extends "res://scripts/ui/common/modal_panel.gd"
## 只渲染Presenter快照并发出意图，不认识库存、钱包或存档。

signal opened
signal selected(id: StringName)
signal claim_requested(id: StringName)
signal retry_save_requested

var heading: Label
var mail_list: ItemList
var subject: Label
var contents: RichTextLabel
var attachments: Label
var note: Label
var claim_button: Button
var retry_button: Button
var _ids: Array[StringName] = []
var _selected: StringName = &""
var _rendering: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pauses_world = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	theme = preload("res://assets/ui/farm_hud.tres").duplicate() as Theme
	theme.default_font = font
	theme.default_font_size = 8
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.06, 0.08, 0.06, 0.55)
	add_child(overlay)
	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -152
	frame.offset_right = 152
	frame.offset_top = -94
	frame.offset_bottom = 94
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("eee3c2")
	paper.border_color = Color("8b775e")
	paper.set_border_width_all(2)
	paper.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", paper)
	add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	frame.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	heading = _label("农场信箱")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(set_open.bind(false))
	top.add_child(close_button)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	mail_list = ItemList.new()
	mail_list.custom_minimum_size = Vector2(100, 112)
	mail_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mail_list.item_selected.connect(_select)
	row.add_child(mail_list)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 180
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	subject = _label("暂无来信")
	subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(subject)
	contents = RichTextLabel.new()
	contents.bbcode_enabled = false
	contents.add_theme_color_override("default_color", Color("514c40"))
	contents.add_theme_font_size_override("normal_font_size", 8)
	contents.custom_minimum_size.y = 72
	contents.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(contents)
	attachments = _label("")
	attachments.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(attachments)
	claim_button = Button.new()
	claim_button.text = "领取全部附件"
	claim_button.pressed.connect(func() -> void: claim_requested.emit(_selected))
	detail.add_child(claim_button)
	note = _label("")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	retry_button = Button.new()
	retry_button.text = "重试保存"
	retry_button.pressed.connect(func() -> void: retry_save_requested.emit())
	column.add_child(retry_button)
	hide()


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("514c40"))
	return label


func set_open(value: bool) -> void:
	var was_open: bool = visible
	_set_modal_open(value)
	if value and visible and not was_open:
		opened.emit()
		mail_list.grab_focus()


func render(data: Dictionary) -> void:
	if heading == null: return
	_rendering = true
	heading.text = "农场信箱 · 未读 %d" % int(data.get("unread", 0))
	_ids.clear()
	mail_list.clear()
	_selected = data.get("selected", &"")
	for row: Dictionary in data.get("letters", []):
		_ids.append(row.id)
		mail_list.add_item(row.text)
		if row.id == _selected: mail_list.select(_ids.size() - 1)
	subject.text = data.get("title", "暂无来信")
	contents.text = data.get("body", "收到的信会保存在这里。")
	attachments.text = data.get("attachments", "")
	claim_button.disabled = not bool(data.get("can_claim", false))
	claim_button.text = data.get("claim_text", "领取全部附件")
	claim_button.tooltip_text = data.get("claim_hint", "")
	note.text = data.get("note", "")
	retry_button.visible = data.get("save_pending", false)
	_rendering = false


func _select(index: int) -> void:
	if not _rendering and index >= 0 and index < _ids.size():
		selected.emit(_ids[index])


func _input(event: InputEvent) -> void:
	if visible and not event.is_echo() and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
