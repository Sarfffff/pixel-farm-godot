extends PanelContainer
## 单任务 HUD View；默认右侧状态牌下方，不占用左上农场手记/J键。

signal journal_requested

var _title: Label
var _body: Label


func _ready() -> void:
	theme = preload("res://scripts/ui/panels/quest_detail.gd").make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -202
	offset_right = -5
	offset_top = 72
	offset_bottom = 72
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	_title = Label.new()
	_title.text = "主目标"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_title)
	var open_button := Button.new()
	open_button.text = "任务日志"
	open_button.pressed.connect(_request_journal)
	heading.add_child(open_button)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)
	render({})


func render(data: Dictionary) -> void:
	var target: Dictionary = data.get("target", {})
	_title.text = String(target.get("status_text", "主目标"))
	_body.text = "尚未追踪任务 · 打开日志选择一个进行中的委托"
	if not target.is_empty():
		_body.text = "%s\n%s · %s\n%s\n下一步：%s" % [
			target.title, target.giver, target.location, target.progress_text, target.next,
		]
	var message: String = String(data.get("message", ""))
	if not message.is_empty(): _body.text += "\n" + message


func _request_journal() -> void:
	journal_requested.emit()
