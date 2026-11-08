extends CanvasLayer
## 独立过场 View；不修改常规 dialogue_panel，不访问任务、背包或金币。

signal advanced
signal selected(index: int)
signal skip_requested

var _panel: PanelContainer
var _rows: VBoxContainer
var _label: Label


func _ready() -> void:
	layer = 130
	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 16
	_panel.offset_right = -16
	_panel.offset_top = -170
	_panel.offset_bottom = -12
	_rows = VBoxContainer.new()
	_panel.add_child(_rows)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	_rows.add_theme_font_override("font", font)
	_rows.add_child(_label)
	close()


func show_line(speaker: String, text: String) -> void:
	_prepare(speaker + "\n" + text if not speaker.is_empty() else text)
	_button("继续", func() -> void: advanced.emit())
	_button("跳过过场", func() -> void: skip_requested.emit())
	_panel.get_child(0).get_child(1).grab_focus()


func show_choices(text: String, options: Array[String], default_option: int) -> void:
	_prepare(text)
	for index: int in options.size():
		_button(options[index], selected.emit.bind(index))
	_button("跳过过场", func() -> void: skip_requested.emit())
	_rows.get_child(default_option + 1).grab_focus()


func close() -> void:
	if is_instance_valid(_panel): _panel.hide()


func _prepare(text: String) -> void:
	for child: Node in _rows.get_children():
		if child != _label:
			_rows.remove_child(child)
			child.queue_free()
	_label.text = text
	_panel.show()


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	_rows.add_child(button)
