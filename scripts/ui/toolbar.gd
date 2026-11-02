extends HBoxContainer
## 工具栏：1 锄头 / 2 水壶 / 3 种子（待开放）/ 4 斧头。
##
## 只做显示，不持有工具状态——工具状态在玩家脚本里，
## 这里通过 player 组查找并订阅 tool_changed。

const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe"]
const SLOT_NAMES: Array[String] = ["Hoe", "WateringCan", "Seeds", "Axe"]
const ACTIVE_TINT := Color(1.0, 1.0, 1.0)
## 用 modulate（含子节点）而不是 self_modulate，让未选中的文字一起变暗，视觉更明确
const IDLE_TINT := Color(0.45, 0.45, 0.45)
const TOOL_LABELS := {&"hoe": "锄头", &"watering_can": "水壶", &"seeds": "种子", &"axe": "斧头"}

var _player: CharacterBody2D
var _hint: Label
var _help: Label


func _ready() -> void:
	for index in SLOT_NAMES.size():
		var icon := get_node("%s/Icon" % SLOT_NAMES[index]) as TextureRect
		var key_label := Label.new()
		key_label.text = str(index + 1)
		key_label.position = Vector2(6, 19)
		key_label.add_theme_font_size_override("font_size", 7)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(key_label)
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[toolbar] 未找到 player 组节点，工具栏不会高亮")
		return
	if not player.has_signal(&"tool_changed"):
		push_warning("[toolbar] 玩家节点缺少 tool_changed 信号")
		return
	_player = player as CharacterBody2D
	_build_help()
	player.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(player.current_tool)


func _on_tool_changed(tool: StringName) -> void:
	if _help != null:
		match tool:
			&"hoe": _help.text = "虚线内无障碍的草地可开垦；已有田地不能重复开垦。"
			&"watering_can": _help.text = "只浇灌干燥耕地；浅蓝色框表示可浇水。"
			&"seeds": _help.text = "种子应播在开垦后的土地上；当前可先准备田地。"
			&"axe": _help.text = "小树需 2 击，大树需 3 击；砍倒后树桩仍会阻挡。"
	for index in SLOT_NAMES.size():
		var slot := get_node_or_null(SLOT_NAMES[index]) as Control
		if slot == null:
			continue
		slot.modulate = ACTIVE_TINT if TOOLS[index] == tool else IDLE_TINT


func _physics_process(_delta: float) -> void:
	if _player == null or _hint == null or not is_instance_valid(_player.interaction):
		return
	var text: String = "%s · %s" % [TOOL_LABELS[_player.current_tool], _player.interaction.interaction_hint(_player.current_tool)]
	if _hint.text != text:
		_hint.text = text


func _build_help() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(6, 5)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.14, 0.12, 0.88)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 1)
	panel.add_child(lines)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	for index in 2:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", Color("eee4c3"))
		lines.add_child(label)
		if index == 0:
			_hint = label
		else:
			_help = label
	get_parent().add_child.call_deferred(panel)
