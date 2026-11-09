extends "res://scripts/ui/common/modal_panel.gd"
## 工作台View：只渲染服务快照，批数是配方批数，材料与成品由服务计算。

signal craft_requested(id: StringName)
signal batch_craft_requested(id: StringName, batches: int)
signal recipe_selected(id: StringName)
signal quantity_changed(batches: int)
signal max_requested
signal retry_save_requested

var _list: ItemList
var _status: Label
var _title: Label
var _purpose: Label
var _source: Label
var _materials: Label
var _products: Label
var _reason: Label
var _limits: Label
var _quantity: SpinBox
var _maximum: Button
var _craft_button: Button
var _retry: Button
var _ids: Array[StringName] = []
var _selected: StringName = &""
var _rendering: bool = false


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	pauses_world = true
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = preload("res://scripts/ui/panels/quest_detail.gd").make_theme()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.color = Color(0.05, 0.07, 0.06, 0.5)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	frame.offset_left = 16
	frame.offset_right = -16
	frame.offset_top = 12
	frame.offset_bottom = -12
	add_child(frame)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 8)
	frame.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	margin.add_child(rows)
	var header := HBoxContainer.new()
	rows.add_child(header)
	var heading := _label("制作工作台 · 农舍木桌", header)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := Button.new()
	close_button.text = "关闭 [Esc]"
	close_button.pressed.connect(set_open.bind(false))
	header.add_child(close_button)
	_status = _label("", rows)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)
	_list = ItemList.new()
	_list.name = "Recipes"
	_list.custom_minimum_size = Vector2(170, 100)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	body.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 5)
	scroll.add_child(detail)
	_title = _label("", detail)
	_purpose = _label("", detail)
	_source = _label("", detail)
	_materials = _label("", detail)
	_products = _label("", detail)
	_reason = _label("", detail)
	_limits = _label("", rows)
	var controls := HBoxContainer.new()
	rows.add_child(controls)
	var batch_label := _label("配方批数", controls)
	batch_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_quantity = SpinBox.new()
	_quantity.name = "BatchQuantity"
	_quantity.min_value = 1
	_quantity.max_value = 999
	_quantity.step = 1
	_quantity.rounded = true
	_quantity.value_changed.connect(func(value: float) -> void:
		if not _rendering: quantity_changed.emit(int(value)))
	controls.add_child(_quantity)
	_maximum = Button.new()
	_maximum.text = "最大批数"
	_maximum.pressed.connect(func() -> void: max_requested.emit())
	controls.add_child(_maximum)
	_craft_button = Button.new()
	_craft_button.name = "Craft"
	_craft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_button.pressed.connect(func() -> void: batch_craft_requested.emit(_selected, int(_quantity.value)))
	controls.add_child(_craft_button)
	_retry = Button.new()
	_retry.text = "重试保存"
	_retry.pressed.connect(func() -> void: retry_save_requested.emit())
	rows.add_child(_retry)
	hide()


func render(data: Dictionary) -> void:
	if _list == null: return
	_rendering = true
	_selected = StringName(data.get("selected", ""))
	var rows: Array[Dictionary] = []
	for row: Dictionary in data.get("recipes", []): rows.append(row)
	var ids: Array[StringName] = []
	for row: Dictionary in rows: ids.append(StringName(row.id))
	# 配方集合不变时原地刷新文字，避免资格刷新清空列表而丢失选中项、滚动与焦点。
	if ids == _ids:
		for index: int in ids.size():
			_list.set_item_text(index, _item_text(rows[index]))
			_list.set_item_tooltip(index, String(rows[index].reason))
	else:
		_ids = ids
		_list.clear()
		for row: Dictionary in rows:
			_list.add_item(_item_text(row))
			_list.set_item_tooltip(_list.item_count - 1, String(row.reason))
	var index: int = _ids.find(_selected)
	if index >= 0: _list.select(index)
	var detail: Dictionary = data.get("detail", {})
	_status.text = String(data.get("message", ""))
	_title.text = String(detail.get("title", "暂无已知配方"))
	_purpose.text = "用途：" + String(detail.get("purpose", ""))
	_source.text = "来源：" + String(detail.get("unlock_source", ""))
	_materials.text = "所需材料\n" + String(data.get("materials_text", ""))
	_products.text = "本次成品：" + String(data.get("products_text", ""))
	_reason.text = String(detail.get("reason", ""))
	_limits.text = "材料上限：%d批 · 当前可制作上限：%d批" % [int(data.get("max_material", 0)), int(data.get("max_craftable", 0))]
	_quantity.max_value = int(data.get("batch_limit", 999))
	_quantity.set_value_no_signal(int(data.get("batches", 1)))
	_maximum.disabled = int(data.get("max_craftable", 0)) == 0
	_craft_button.text = "制作 · " + String(detail.get("title", ""))
	_craft_button.disabled = not bool(detail.get("ok", false))
	_craft_button.tooltip_text = String(detail.get("reason", ""))
	_retry.visible = bool(data.get("save_pending", false))
	_rendering = false


func _item_text(row: Dictionary) -> String:
	return String(row.title) + ("" if row.available else " · 未满足")


func _select(index: int) -> void:
	if not _rendering and index >= 0 and index < _ids.size(): recipe_selected.emit(_ids[index])


func _label(text: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
