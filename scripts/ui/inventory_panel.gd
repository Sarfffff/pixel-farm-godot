extends Control
## 分类背包、拖拽换位及快捷位绑定，共用 Inventory 与 ItemSlot。

const ItemSlot := preload("res://scripts/ui/item_slot.gd")
const COLUMNS: int = 6
const CATEGORIES: Array[StringName] = [&"all", &"tool", &"seed", &"crop", &"material"]
const CATEGORY_NAMES: Array[String] = ["全部", "工具", "种子", "收获", "材料"]
@onready var _grid: GridContainer = %Grid
@onready var _title: Label = %Title
@onready var _item_name: Label = %ItemName
@onready var _item_description: Label = %ItemDescription
@onready var _overlay: ColorRect = $Overlay
var _inventory: Inventory
var _slots: Array[Panel] = []
var _hotbar_slots: Array[Panel] = []
var _view_indices: Array[int] = []
var _selected: int = 0
var _hovered: int = -1
var _category: StringName = &"all"
var _idle_style: StyleBox
var _active_style: StyleBox
var _hover_style: StyleBox


func _ready() -> void:
	_idle_style = get_theme_stylebox("idle", "InventorySlot")
	_active_style = get_theme_stylebox("selected", "InventorySlot")
	_hover_style = get_theme_stylebox("hover", "InventorySlot")
	_inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	if _inventory == null:
		hide()
		return
	for index in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORY_NAMES[index]
		button.custom_minimum_size = Vector2(32, 14)
		button.add_theme_font_size_override("font_size", 7)
		button.pressed.connect(set_category.bind(CATEGORIES[index]))
		$Frame/VBox/Tabs.add_child(button)
	for index in _inventory.slot_count():
		var slot := ItemSlot.new()
		slot.inventory = _inventory
		slot.view_index = index
		slot.selected.connect(_select)
		slot.activated.connect(_equip)
		_grid.add_child(slot)
		_slots.append(slot)
	for index in Inventory.HOTBAR_SIZE:
		var slot := ItemSlot.new()
		slot.inventory = _inventory
		slot.view_index = index
		slot.hotbar_index = index
		slot.selected.connect(_inventory.select_hotbar)
		%Hotbar.add_child(slot)
		_hotbar_slots.append(slot)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_inventory.changed.connect(_refresh)
	_inventory.hotbar_changed.connect(_refresh_hotbar)
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades != null:
		upgrades.changed.connect(_refresh)
	hide()
	_refresh()


func _input(event: InputEvent) -> void:
	if _inventory == null or event.is_echo():
		return
	if event.is_action_pressed(&"toggle_inventory"):
		set_open(not visible)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	for index in Inventory.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("tool_%d" % (index + 1))):
			bind_selected(index)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
	elif event.is_action_pressed(&"ui_left"):
		_select(_selected - 1)
	elif event.is_action_pressed(&"ui_right"):
		_select(_selected + 1)
	elif event.is_action_pressed(&"ui_up"):
		_select(_selected - COLUMNS)
	elif event.is_action_pressed(&"ui_down"):
		_select(_selected + COLUMNS)
	elif event.is_action_pressed(&"ui_accept"):
		_equip(_selected)
	elif event.is_action_pressed(&"discard_item"):
		_discard(_selected)
	else:
		return
	get_viewport().set_input_as_handled()


## 丢弃 1 个（不整摞丢，避免手滑清空背包）；永久工具拒绝丢弃。
func _discard(index: int) -> void:
	if _inventory == null or index < 0 or index >= _inventory.slot_count():
		return
	var slot: Dictionary = _inventory.item_at(index)
	if slot.is_empty():
		return
	var id: StringName = slot.get(&"id", &"")
	if id == &"":
		return
	if Inventory.TOOL_IDS.has(id):
		_show_message("工具不能丢")
		return
	var item := _inventory.definition(id)
	if _inventory.remove_item(id, 1):
		_show_message("丢弃了 1 个 %s" % item.display_name)
	_refresh()


func _show_message(text: String) -> void:
	var toast := get_node_or_null("../Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.call(&"show_message", text)


func set_open(open: bool) -> void:
	visible = open
	_hovered = -1
	for slot in _slots:
		slot._hovered = false
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null:
		player.set_input_locked(open)
	var toolbar := get_node_or_null("../Toolbar")
	if toolbar != null:
		toolbar.set_ui_visible(not open)
	if not open:
		return
	for other_name: String in ["ShopPanel", "DialoguePanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
		var other := get_node_or_null("../" + other_name) as Control
		if other != null and other.visible:
			other.set_open(false)
	var toast := get_node_or_null("../Toast")
	if toast != null:
		toast.clear()
	_refresh()


func set_category(category: StringName) -> void:
	if not CATEGORIES.has(category):
		return
	_category = category
	_selected = 0
	_refresh()


func _refresh() -> void:
	if _inventory == null:
		return
	_view_indices.clear()
	var empty: Array[int] = []
	var used: int = 0
	for index in _inventory.slot_count():
		var record: Dictionary = _inventory.item_at(index)
		if record.is_empty():
			empty.append(index)
			continue
		used += 1
		var item: ItemData = _inventory.definition(record[&"id"])
		if item != null and _inventory.matches_category(item.id, _category):
			_view_indices.append(index)
	if _category == &"all":
		# 全部页保留真实格子顺序；分类页不移动数据，只映射格子。
		_view_indices.clear()
		for index in _inventory.slot_count():
			_view_indices.append(index)
	else:
		_view_indices.append_array(empty)
	for index in _slots.size():
		var slot: Panel = _slots[index]
		slot.storage_index = _view_indices[index] if index < _view_indices.size() else -1
		slot.category_filter = _category
		var record: Dictionary = _inventory.item_at(slot.storage_index)
		slot.item_id = record.get(&"id", &"")
		slot.refresh()
	_title.text = "背包 %d/%d" % [used, _inventory.slot_count()]
	for index in CATEGORIES.size():
		var button: Button = $Frame/VBox/Tabs.get_child(index)
		button.add_theme_stylebox_override("normal", _active_style if CATEGORIES[index] == _category else get_theme_stylebox("normal", "Button"))
	_apply_slot_styles()
	_refresh_hotbar()
	_update_details()


func _refresh_hotbar() -> void:
	if _inventory == null or _inventory.hotbar.size() != Inventory.HOTBAR_SIZE:
		return
	for index in _hotbar_slots.size():
		var slot: Panel = _hotbar_slots[index]
		slot.item_id = _inventory.hotbar[index]
		slot.is_selected = index == _inventory.active_slot
		slot.refresh()


func _select(index: int) -> void:
	_selected = clampi(index, 0, _slots.size() - 1)
	_apply_slot_styles()
	_update_details()


func _apply_slot_styles() -> void:
	for index in _slots.size():
		_slots[index].is_selected = index == _selected
		_slots[index].refresh_style()


func _selected_item() -> StringName:
	if _selected >= _view_indices.size():
		return &""
	return _inventory.item_at(_view_indices[_selected]).get(&"id", &"")


func _update_details() -> void:
	var id: StringName = _selected_item()
	var item: ItemData = _inventory.definition(id)
	%DetailIcon.texture = _inventory.item_icon(id)
	if item == null:
		_item_name.text = "空槽位"
		_item_description.text = "拖动物品可整理位置。工具、种子和收获物都可以放入快捷栏，数量与背包同步。"
		return
	_item_name.text = _inventory.item_name(id)
	if item.category != &"tool":
		_item_name.text += " ×%d" % int(_inventory.item_at(_view_indices[_selected]).get(&"count", 0))
	_item_description.text = item.description


func bind_selected(index: int) -> bool:
	var id: StringName = _selected_item()
	if id == &"" or not _inventory.assign_hotbar(index, id):
		%BindingHint.text = "先选择背包中的物品，再按 1–8 绑定"
		return false
	%BindingHint.text = "%s → 快捷位 %d" % [_inventory.item_name(id), index + 1]
	return true


func _equip(index: int) -> void:
	_select(index)
	var id: StringName = _selected_item()
	if id == &"":
		return
	var shortcut: int = _inventory.hotbar.find(id)
	if shortcut < 0:
		shortcut = _inventory.active_slot
		if not _inventory.assign_hotbar(shortcut, id):
			return
	_inventory.select_hotbar(shortcut)
	set_open(false)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
