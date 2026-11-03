extends Control
## 背包面板：6×4 格，图标 + 数量角标，鼠标点击或方向键选择，底部显示物品说明。
##
## 根节点是全屏 Control（含半透明遮罩），Frame 才是可见的木质面板。
## B / Esc / 点击面板外空白都能关闭；打开时锁住玩家输入并隐藏工具栏。

const COLUMNS: int = 6
const EMPTY_TEXT: String = "空槽位"
## 槽位尺寸：18×18 塞下 16×16 图标，并且让整块面板保持小巧。
const SLOT_SIZE: int = 18

@onready var _grid: GridContainer = %Grid
@onready var _title: Label = %Title
@onready var _item_name: Label = %ItemName
@onready var _item_description: Label = %ItemDescription
@onready var _overlay: ColorRect = $Overlay

var _inventory: Inventory
var _slots: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _selected: int = 0
var _hovered: int = -1
var _idle_style: StyleBoxTexture
var _active_style: StyleBoxTexture
var _hover_style: StyleBoxTexture


func _ready() -> void:
	_idle_style = get_theme_stylebox("idle", "InventorySlot") as StyleBoxTexture
	_active_style = get_theme_stylebox("selected", "InventorySlot") as StyleBoxTexture
	_hover_style = get_theme_stylebox("hover", "InventorySlot") as StyleBoxTexture
	if _idle_style == null or _active_style == null:
		push_warning("[inventory_panel] 缺少 InventorySlot 主题样式，槽位会退回默认外观")
	_inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	if _inventory == null:
		push_error("[inventory_panel] 未找到 inventory 组节点，背包面板不可用")
		hide()
		return
	_build_slots()
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_inventory.changed.connect(_refresh)
	hide()
	_refresh()


func _input(event: InputEvent) -> void:
	if _inventory == null:
		return
	if event.is_action_pressed(&"toggle_inventory"):
		set_open(not visible)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left"):
		_select(_selected - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right"):
		_select(_selected + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		_select(_selected - COLUMNS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_select(_selected + COLUMNS)
		get_viewport().set_input_as_handled()


## 开关背包：同步玩家输入锁与工具栏可见性，避免面板挡住时还能走路。
func set_open(open: bool) -> void:
	_hovered = -1
	visible = open
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(open)
	var toolbar: Node = get_node_or_null("../Toolbar")
	if toolbar != null and toolbar.has_method(&"set_ui_visible"):
		toolbar.set_ui_visible(not open)
	if open:
		# 与商店/对话互斥：面板都锁输入，叠在一起会互相解锁。
		var shop := get_node_or_null("../ShopPanel") as Control
		if shop != null and shop.visible:
			shop.call(&"set_open", false)
		for other_name: String in ["DialoguePanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
			var other := get_node_or_null("../%s" % other_name) as Control
			if other != null and other.visible:
				other.call(&"set_open", false)
		# 打开面板时收起还没淡出的入包提示，避免压在面板上。
		var toast := get_node_or_null("../Toast")
		if toast != null and toast.has_method(&"clear"):
			toast.clear()
		_refresh()
		_select(_selected)


func _build_slots() -> void:
	# 数量角标必须用面板同一套字体，否则默认字体的行高会把数字顶到格子外面。
	var font: Font = _item_name.get_theme_font("font")
	for index: int in _inventory.slot_count():
		# 用 Panel（不是 PanelContainer）：格子内的图标与数量需要像素级定位，
		# 容器会重排子节点，导致 16px 图标与角标对不齐。
		var slot: Panel = Panel.new()
		slot.name = "Slot%02d" % index
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.add_theme_stylebox_override("panel", _idle_style)
		slot.gui_input.connect(_on_slot_gui_input.bind(index))
		slot.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
		slot.mouse_exited.connect(_on_slot_mouse_exited.bind(index))

		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(1, 1)
		icon.size = Vector2(16, 16)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		slot.add_child(icon)

		var count: Label = Label.new()
		count.name = "Count"
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.position = Vector2(2, 2)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		if font != null:
			count.add_theme_font_override("font", font)
		count.add_theme_font_size_override("font_size", 7)
		count.add_theme_color_override("font_color", Color("eee4c3"))
		count.add_theme_color_override("font_outline_color", Color(0.10, 0.09, 0.07, 0.9))
		count.add_theme_constant_override("outline_size", 1)
		slot.add_child(count)

		_grid.add_child(slot)
		count.size = Vector2(16, 16)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(count)


func _refresh() -> void:
	if _inventory == null:
		return
	for index in _slots.size():
		var slot: Dictionary = _inventory.item_at(index)
		if slot.is_empty():
			_icons[index].texture = null
			_counts[index].text = ""
			continue
		var definition: ItemData = _inventory.definition(slot[&"id"])
		_icons[index].texture = definition.icon if definition != null else null
		var amount: int = int(slot[&"count"])
		_counts[index].text = str(amount) if amount > 1 else ""
	_update_details()


func _select(index: int) -> void:
	if _slots.is_empty():
		return
	_selected = clampi(index, 0, _slots.size() - 1)
	_apply_slot_styles()
	_update_details()


## 槽位样式来自 inventory_theme.tres 的 InventorySlot 类型：选中 > 悬停 > 常态。
func _apply_slot_styles() -> void:
	for slot_index: int in _slots.size():
		var style: StyleBox = _idle_style
		if slot_index == _selected:
			style = _active_style
		elif slot_index == _hovered:
			style = _hover_style
		if style != null:
			_slots[slot_index].add_theme_stylebox_override("panel", style)


func _on_slot_mouse_entered(index: int) -> void:
	_hovered = index
	_apply_slot_styles()


func _on_slot_mouse_exited(index: int) -> void:
	if _hovered == index:
		_hovered = -1
		_apply_slot_styles()


## 点击遮罩（面板外的空白）关闭背包；面板与槽位本身会吞掉点击，不会误关。
func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)


func _update_details() -> void:
	if _inventory == null:
		return
	var slot: Dictionary = _inventory.item_at(_selected)
	if slot.is_empty():
		_title.text = _title_text()
		_item_name.text = EMPTY_TEXT
		_item_description.text = "砍倒树木可以获得木材；种子已经放在背包里。"
		return
	var definition: ItemData = _inventory.definition(slot[&"id"])
	if definition == null:
		_title.text = _title_text()
		_item_name.text = EMPTY_TEXT
		_item_description.text = ""
		return
	_title.text = _title_text()
	_item_name.text = "%s ×%d" % [definition.display_name, int(slot[&"count"])]
	_item_description.text = definition.description


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_select(index)


func _title_text() -> String:
	var used: int = 0
	for index in _inventory.slot_count():
		if not _inventory.item_at(index).is_empty():
			used += 1
	return "背包 %d/%d" % [used, _inventory.slot_count()]



