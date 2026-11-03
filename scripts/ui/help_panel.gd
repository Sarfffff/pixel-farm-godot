extends Control
## 按键说明：F1 或暂停菜单打开，列出当前所有操作。
##
## 内容集中写在 ROWS 里，改键位只改这张表，不用碰场景。

const ROWS: Array[Array] = [
	["移动", "WASD / 方向键"],
	["交互 · 收获 · 捡蛋", "E"],
	["和杂货铺老板说话", "E（走近他）"],
	["使用当前工具", "空格 / 鼠标左键"],
	["快捷栏", "1–8 / 点击格子，Q/E 切换"],
	["换种子", "拿种子袋时 Q / E"],
	["背包", "B"],
	["背包分类与绑定", "分类页签；选物品按 1–8 / 拖拽"],
	["镜头与窗口", "滚轮 / +/- 缩放，Home 复位，F11 全屏"],
	["清理田边杂草", "靠近按 E，获得纤维"],
	["农场手记", "J 展开 / 收起"],
	["铜水壶升级", "商店底部 · 升级后一次浇三格"],
	["木箱 / 腌制台", "屋右 E；番茄×3 过夜腌制"],
	["采集 / 钓鱼", "野外 E / 竹竿在池塘北岸使用"],
	["暂停菜单", "Esc"],
	["按键说明", "F1"],
]

@onready var _rows: VBoxContainer = %Rows
@onready var _overlay: ColorRect = $Overlay


func _ready() -> void:
	# 面板自己会把游戏树暂停，暂停后仍要能收到 F1 / Esc，所以走 ALWAYS。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_build_rows()
	hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_help"):
		if visible:
			set_open(false)
		elif _can_open():
			set_open(true)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if open:
		# 先收掉其他面板，再设暂停：暂停菜单关闭时会把 paused 置回 false。
		for panel_name: String in ["InventoryPanel", "ShopPanel", "DaySummary", "DialoguePanel", "PauseMenu", "OrderPanel", "CommunityPanel"]:
			var other := get_node_or_null("../%s" % panel_name) as Control
			if other == null or not other.visible:
				continue
			if panel_name == "PauseMenu":
				other.call(&"close")
			else:
				other.call(&"set_open", false)
	visible = open
	# 帮助面板也暂停游戏树：翻说明的时候不该被时间推着走。
	get_tree().paused = open
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(open)
	var toolbar := get_node_or_null("../Toolbar")
	if toolbar != null and toolbar.has_method(&"set_ui_visible"):
		toolbar.set_ui_visible(not open)


## 背包/商店/日报/对话/暂停开着时，F1 先交给它们处理。
func _can_open() -> bool:
	for panel: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		if panel is Control and panel.visible:
			return false
	for panel_name: String in ["InventoryPanel", "ShopPanel", "DaySummary", "DialoguePanel", "PauseMenu", "OrderPanel", "CommunityPanel"]:
		var panel := get_node_or_null("../%s" % panel_name) as Control
		if panel != null and panel.visible:
			return false
	return true


func _build_rows() -> void:
	var font := _rows.get_theme_font("font")
	for row: Array in ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)

		var action := Label.new()
		action.text = String(row[0])
		action.custom_minimum_size = Vector2(96, 0)
		action.add_theme_font_override("font", font)
		action.add_theme_font_size_override("font_size", 6)
		action.add_theme_color_override("font_color", Color(0.88, 0.82, 0.66, 1))
		line.add_child(action)

		var keys := Label.new()
		keys.text = String(row[1])
		keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.add_theme_font_override("font", font)
		keys.add_theme_font_size_override("font_size", 6)
		keys.add_theme_color_override("font_color", Color(0.96, 0.91, 0.74, 1))
		line.add_child(keys)

		_rows.add_child(line)


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
