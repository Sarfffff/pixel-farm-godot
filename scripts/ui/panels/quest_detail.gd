extends VBoxContainer
## 详情 View：只渲染快照和发按钮意图，不持有任务服务。

signal accept_requested(id: StringName)
signal deliver_requested(id: StringName)
signal track_requested(id: StringName)
signal untrack_requested

var _id: StringName = &""
var _heading: Label
var _body: Label
var _accept: Button
var _deliver: Button
var _track: Button
var _untrack: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 10)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_heading)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	# 两行按钮允许窄窗口和中文标签换行，不挤出详情边界。
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 5)
	add_child(actions)
	_accept = _button(actions, "接取委托", _request_accept)
	_deliver = _button(actions, "交付材料", _request_deliver)
	_track = _button(actions, "追踪此任务", _request_track)
	_untrack = _button(actions, "取消追踪", _request_untrack)


func render(data: Dictionary) -> void:
	_id = StringName(data.get("id", ""))
	_heading.text = String(data.get("title", "暂无任务"))
	_body.text = "%s · %s\n委托人：%s\n地点：%s\n\n%s\n\n%s\n%s\n\n奖励：%s\n\n下一步：%s" % [
		data.get("category", "主线"), data.get("status_text", ""), data.get("giver", "—"),
		data.get("location", "—"), data.get("summary", ""), data.get("progress_heading", "材料进度"), data.get("progress_text", "—"),
		data.get("reward_text", "—"), data.get("next", "查看委托列表"),
	]
	_accept.disabled = not bool(data.get("can_accept", false))
	_deliver.disabled = not bool(data.get("can_deliver", false))
	_track.disabled = not bool(data.get("can_track", false)) or bool(data.get("tracked", false))
	_untrack.disabled = not bool(data.get("tracked", false))


func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _request_accept() -> void:
	accept_requested.emit(_id)


func _request_deliver() -> void:
	deliver_requested.emit(_id)


func _request_track() -> void:
	track_requested.emit(_id)


func _request_untrack() -> void:
	untrack_requested.emit()


static func make_theme() -> Theme:
	var skin := preload("res://assets/ui/farm_hud.tres").duplicate() as Theme
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	skin.default_font = font
	skin.default_font_size = 8
	for type: String in ["Label", "Button", "ItemList"]:
		for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_selected_color", "font_focus_color"]:
			skin.set_color(color, type, Color("514c40"))
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("eee3c2")
	paper.border_color = Color("8e6b4c")
	paper.set_border_width_all(1)
	paper.set_content_margin_all(5)
	skin.set_stylebox("panel", "PanelContainer", paper)
	skin.set_stylebox("panel", "ItemList", paper)
	var selected := paper.duplicate() as StyleBoxFlat
	selected.bg_color = Color("cad698")
	skin.set_stylebox("selected", "ItemList", selected)
	skin.set_stylebox("selected_focus", "ItemList", selected)
	var button := paper.duplicate() as StyleBoxFlat
	button.bg_color = Color("d0ad7e")
	skin.set_stylebox("normal", "Button", button)
	skin.set_stylebox("hover", "Button", selected)
	skin.set_stylebox("pressed", "Button", selected)
	return skin
