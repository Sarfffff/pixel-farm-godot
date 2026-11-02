extends HBoxContainer
## 工具栏（V0.4）：显示当前工具的选中状态。
##
## 只做显示，不持有工具状态——工具状态在玩家脚本里，
## 这里通过 player 组查找并订阅 tool_changed。

const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds"]
const SLOT_NAMES: Array[String] = ["Hoe", "WateringCan", "Seeds"]
const ACTIVE_TINT := Color(1.0, 1.0, 1.0)
## 用 modulate（含子节点）而不是 self_modulate，让未选中的文字一起变暗，视觉更明确
const IDLE_TINT := Color(0.45, 0.45, 0.45)


func _ready() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[toolbar] 未找到 player 组节点，工具栏不会高亮")
		return
	if not player.has_signal(&"tool_changed"):
		push_warning("[toolbar] 玩家节点缺少 tool_changed 信号")
		return
	player.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(player.current_tool)


func _on_tool_changed(tool: StringName) -> void:
	for index in SLOT_NAMES.size():
		var slot := get_node_or_null(SLOT_NAMES[index]) as Control
		if slot == null:
			continue
		slot.modulate = ACTIVE_TINT if TOOLS[index] == tool else IDLE_TINT
