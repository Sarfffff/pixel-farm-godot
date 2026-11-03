extends PanelContainer
## 底部工具栏：一条木质底板 + 5 个格子（锄头 / 水壶 / 种子 / 斧头 / 石镐）。
##
## 只做显示，不持有工具状态——工具状态在玩家脚本里，
## 这里通过 player 组查找并订阅 tool_changed。
##
## 当前工具用亮木框（主题里的 InventorySlot/selected）标出，格子图标保持原亮度；
## 工具说明不常驻：**点一下格子**才在工具栏上方弹出气泡，几秒后淡出。
## 左上角只留一行"附近可交互"的即时提示，没有可交互对象时整条隐藏。

const TOOLS: Array[StringName] = [&"hoe", &"watering_can", &"seeds", &"axe", &"stone_pickaxe"]
const SLOT_NAMES: Array[String] = ["Hoe", "WateringCan", "Seeds", "Axe", "StonePickaxe"]
const SLOTS_PATH: String = "Slots"
const TOOL_LABELS: Dictionary[StringName, String] = {&"hoe": "锄头", &"watering_can": "水壶", &"seeds": "种子", &"axe": "斧头", &"stone_pickaxe": "石镐"}
## 点击格子后的说明：一句话用途 + 体力开销（数值取自 farm_tiller.STAMINA_COST）。
const TOOL_TIPS: Dictionary[StringName, String] = {
	&"hoe": "开垦草地，翻出能播种的地 · 体力 4",
	&"watering_can": "浇已种下的作物，浇过夜里才长 · 体力 2",
	&"seeds": "在翻好的地上播种，种子从背包扣 · 体力 2",
	&"axe": "砍树取木材，小树 2 下、大树 3 下 · 体力 8",
	&"stone_pickaxe": "敲碎石头取石料，敲 3 下 · 体力 6",
}
## 气泡停留时间与淡出时长。
const TIP_HOLD: float = 4.5
const TIP_FADE: float = 0.35

var _player: CharacterBody2D
var _hint: Label
var _hint_panel: PanelContainer
var _tip: Label
var _tip_panel: PanelContainer
var _tip_tween: Tween


func _ready() -> void:
	for index in SLOT_NAMES.size():
		var slot := _slot(index)
		if slot == null:
			continue
		# 按键序号压在格子右上角，和星露谷一样
		var icon := slot.get_node("Icon") as TextureRect
		var key_label := Label.new()
		key_label.text = str(index + 1)
		key_label.position = Vector2(13, 1)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.add_theme_font_size_override("font_size", 6)
		key_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.74))
		key_label.add_theme_color_override("font_outline_color", Color(0.09, 0.08, 0.07, 0.9))
		key_label.add_theme_constant_override("outline_size", 2)
		icon.add_child(key_label)
		# 格子可点：点一下切到该工具，并弹出它的说明气泡
		slot.tooltip_text = ""
		slot.gui_input.connect(_on_slot_gui_input.bind(index))

	_build_ui()

	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[toolbar] 未找到 player 组节点，工具栏不会高亮")
		return
	if not player.has_signal(&"tool_changed"):
		push_warning("[toolbar] 玩家节点缺少 tool_changed 信号")
		return
	_player = player as CharacterBody2D
	player.tool_changed.connect(_on_tool_changed)
	_on_tool_changed(player.current_tool)


func _on_tool_changed(tool: StringName) -> void:
	var idle_style := get_theme_stylebox(&"idle", &"InventorySlot")
	var active_style := get_theme_stylebox(&"selected", &"InventorySlot")
	for index in SLOT_NAMES.size():
		var slot := _slot(index)
		if slot == null:
			continue
		var active: bool = TOOLS[index] == tool
		if active and active_style != null:
			slot.add_theme_stylebox_override("panel", active_style)
		elif idle_style != null:
			slot.add_theme_stylebox_override("panel", idle_style)
		# 未选中的格子略压暗，让亮木框在缩放后一眼能看出来
		slot.modulate = Color.WHITE if active else Color(0.86, 0.86, 0.86)


func _physics_process(_delta: float) -> void:
	if _player == null or _hint == null:
		return
	# 附近有商店等交互点时优先显示它，否则显示当前工具的状态说明。
	var ambient: String = _player.nearby_hint() if _player.has_method(&"nearby_hint") else ""
	var text: String = ambient
	if text == "" and is_instance_valid(_player.interaction):
		text = "%s · %s" % [TOOL_LABELS[_player.current_tool], _player.interaction.interaction_hint(_player.current_tool)]
	if text != _hint.text:
		_hint.text = text
	if _hint_panel != null:
		_hint_panel.visible = text != ""


## 打开背包等面板时整体收起：提示条是 UI 的兄弟节点，必须一起隐藏，否则会盖住面板标题。
func set_ui_visible(shown: bool) -> void:
	visible = shown
	if _hint_panel != null:
		_hint_panel.visible = shown and _hint.text != ""
	if _tip_panel != null:
		_tip_panel.visible = false


## 点格子：切到该工具（动作中被拒绝也没关系），并弹出说明气泡。
func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	# 吃掉这次点击，避免同一个左键又触发"使用工具"
	accept_event()
	if _player != null:
		_player.call(&"_select_tool", index)
	_show_tip(index)


func _show_tip(index: int) -> void:
	if _tip_panel == null or not _tip_panel.is_inside_tree():
		return
	_tip.text = TOOL_TIPS.get(TOOLS[index], TOOL_LABELS[TOOLS[index]])
	_tip_panel.reset_size()
	var tip_size: Vector2 = _tip_panel.size
	var view: Vector2 = get_viewport_rect().size
	var anchor := Vector2(view.x * 0.5, get_global_rect().position.y)
	var slot := _slot(index)
	if slot != null:
		var rect: Rect2 = slot.get_global_rect()
		anchor = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 3.0)
	var pos := Vector2(anchor.x - tip_size.x * 0.5, anchor.y - tip_size.y)
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view.x - tip_size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, view.y - tip_size.y - 4.0)
	_tip_panel.position = pos
	_tip_panel.visible = true
	_tip_panel.modulate.a = 1.0
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_interval(TIP_HOLD)
	_tip_tween.tween_property(_tip_panel, "modulate:a", 0.0, TIP_FADE)
	_tip_tween.tween_callback(_hide_tip)


func _hide_tip() -> void:
	if _tip_panel != null:
		_tip_panel.visible = false


func _slot(index: int) -> PanelContainer:
	return get_node_or_null("%s/%s" % [SLOTS_PATH, SLOT_NAMES[index]]) as PanelContainer


func _build_ui() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	_hint = _make_label(font, Color("f2e9cf"))
	_hint_panel = _wrap_panel(_make_style(Color(0.16, 0.14, 0.12, 0.78)), _hint, Vector2(5, 4))
	_hint_panel.visible = false
	_tip = _make_label(font, Color("f6efd8"))
	_tip_panel = _wrap_panel(_make_style(Color(0.11, 0.10, 0.08, 0.92)), _tip, Vector2(-200, -200))
	_tip_panel.visible = false


func _make_label(font: SystemFont, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.07, 0.06, 0.85))
	label.add_theme_constant_override("outline_size", 2)
	return label


func _make_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.content_margin_left = 3
	style.content_margin_right = 3
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _wrap_panel(style: StyleBoxFlat, label: Label, pos: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(label)
	get_parent().add_child.call_deferred(panel)
	return panel
