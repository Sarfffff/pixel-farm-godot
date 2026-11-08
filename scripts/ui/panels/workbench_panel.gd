extends "res://scripts/ui/common/modal_panel.gd"
## 工作台View只显示快照并报告制作意图。

signal craft_requested(id: StringName)
var _rows: VBoxContainer


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	pauses_world = true
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = preload("res://scripts/ui/panels/quest_detail.gd").make_theme()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.07, 0.06, 0.5)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(PRESET_CENTER)
	frame.position = Vector2(-165, -95)
	frame.custom_minimum_size = Vector2(330, 190)
	add_child(frame)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	frame.add_child(_rows)
	hide()


func render(data: Dictionary) -> void:
	if _rows == null: return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_label("种子工作台 · 农舍木桌")
	_label(String(data.get("message", "收获留种，再投入下一轮种植。")))
	for row: Dictionary in data.get("recipes", []):
		_label(String(row.text))
		var button := Button.new()
		button.text = "制作 · " + String(row.title)
		button.disabled = not bool(row.available)
		button.tooltip_text = row.hint
		button.pressed.connect(func() -> void: craft_requested.emit(row.id))
		_rows.add_child(button)
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(set_open.bind(false))
	_rows.add_child(close_button)


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
