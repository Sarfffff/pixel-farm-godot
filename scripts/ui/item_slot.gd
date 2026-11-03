extends Panel
## 背包和快捷栏共用的槽位：独立布局图标、右上按键、右下数量。

signal selected(index: int)
signal activated(index: int)

const SLOT_SIZE: int = 22
var inventory: Inventory
var item_id: StringName = &""
var storage_index: int = -1
var hotbar_index: int = -1
var view_index: int = 0
var category_filter: StringName = &"all"
var is_selected: bool = false
var _hovered: bool = false
var _icon: TextureRect
var _count: Label
var _key: Label


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.position = Vector2(3, 3)
	_icon.size = Vector2(16, 16)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	_count = _label("Count")
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_key = _label("Key")
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	resized.connect(_layout_overlays)
	mouse_entered.connect(func() -> void: _hovered = true; refresh_style())
	mouse_exited.connect(func() -> void: _hovered = false; refresh_style())
	_layout_overlays()
	refresh()


func _label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color("fff1d0"))
	label.add_theme_color_override("font_outline_color", Color("47334f"))
	label.add_theme_constant_override("outline_size", 1)
	add_child(label)
	return label


func _layout_overlays() -> void:
	if _key == null:
		return
	_key.position = Vector2(size.x - 9, 0)
	_key.size = Vector2(7, 9)
	_count.position = Vector2(1, size.y - 10)
	_count.size = Vector2(size.x - 3, 9)
	_icon.position = ((size - Vector2(16, 16)) * 0.5).floor()


func refresh() -> void:
	if not is_node_ready() or inventory == null:
		return
	var count: int = inventory.count_of(item_id) if hotbar_index >= 0 else int(inventory.item_at(storage_index).get(&"count", 0))
	_icon.texture = inventory.item_icon(item_id)
	_icon.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.30)
	var item: ItemData = inventory.definition(item_id)
	_count.text = str(count) if item != null and item.category != &"tool" and (count > 1 or hotbar_index >= 0) else ""
	_key.text = str(hotbar_index + 1) if hotbar_index >= 0 else ""
	tooltip_text = inventory.item_name(item_id) if item != null else "空快捷位 · 从背包拖入物品"
	refresh_style()


func refresh_style() -> void:
	var state: StringName = &"selected" if is_selected else (&"hover" if _hovered else &"idle")
	var style: StyleBox = get_theme_stylebox(state, &"InventorySlot")
	if style != null:
		add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		selected.emit(view_index)
		if event.double_click:
			activated.emit(view_index)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and hotbar_index >= 0:
		inventory.assign_hotbar(hotbar_index, &"")
		accept_event()


func _get_drag_data(_position: Vector2) -> Variant:
	if inventory == null or item_id == &"" or inventory.count_of(item_id) <= 0:
		return null
	var preview := TextureRect.new()
	preview.texture = inventory.item_icon(item_id)
	preview.custom_minimum_size = Vector2(24, 24)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return {&"inventory": inventory, &"id": item_id, &"slot": storage_index, &"hotbar": hotbar_index}


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get(&"inventory") != inventory:
		return false
	var id := StringName(str(data.get(&"id", "")))
	var item: ItemData = inventory.definition(id)
	if item == null or inventory.count_of(id) <= 0:
		return false
	return hotbar_index >= 0 or (storage_index >= 0 and inventory.matches_category(id, category_filter))


func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_drop_data(position, data):
		return
	if hotbar_index >= 0:
		var origin: int = int(data.get(&"hotbar", -1))
		if origin >= 0:
			inventory.swap_hotbar(origin, hotbar_index)
		else:
			inventory.assign_hotbar(hotbar_index, StringName(str(data[&"id"])))
	else:
		var origin: int = int(data.get(&"slot", -1))
		if origin < 0:
			origin = inventory.find_item(StringName(str(data[&"id"])))
		inventory.swap_slots(origin, storage_index)
