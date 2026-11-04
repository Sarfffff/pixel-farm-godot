extends "res://scripts/ui/common/modal_panel.gd"
## 按键说明：F1 或暂停菜单打开，列出当前所有操作。
##
## 内容集中写在 ROWS 里，改键位只改这张表，不用碰场景。

const ROWS: Array[Array] = [
	["移动", "WASD / 方向键"],
	["交互 · 收获 · 拾取掉落", "E（路标也可切换区域）"],
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
	["野外区域 / 采集", "农场东侧路标 E；木用斧、矿用镐"],
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
	_set_modal_open(open)


func _can_open() -> bool:
	return _can_open_modal()


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
		action.add_theme_color_override("font_color", Color("514c40"))
		line.add_child(action)

		var keys := Label.new()
		keys.text = String(row[1])
		keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.add_theme_font_override("font", font)
		keys.add_theme_font_size_override("font_size", 6)
		keys.add_theme_color_override("font_color", Color("514c40"))
		line.add_child(keys)

		_rows.add_child(line)


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
