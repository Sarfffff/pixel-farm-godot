extends "res://scripts/ui/common/modal_panel.gd"
## 动态储物箱View；复用既有仓储交互，不引用库存或存档。

signal deposit_requested(item: StringName, all: bool)
signal withdraw_requested(item: StringName, all: bool)
signal retry_save_requested
signal manage_requested
signal closed
var _bag: ItemList
var _storage: ItemList
var _note: Label
var _retry: Button
var _bag_ids: Array[StringName] = []
var _storage_ids: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pauses_world = true
	theme = preload("res://assets/ui/farm_hud.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.08, 0.06, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -150
	frame.offset_right = 150
	frame.offset_top = -82
	frame.offset_bottom = 82
	add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	var title := Label.new()
	title.text = "储物箱 · 独立24格"
	column.add_child(title)
	var lists := HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lists)
	_bag = _list(lists)
	_storage = _list(lists)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	actions.add_child(_button("存1 →", _deposit.bind(false)))
	actions.add_child(_button("存整叠 →", _deposit.bind(true)))
	actions.add_child(_button("← 取1", _withdraw.bind(false)))
	actions.add_child(_button("← 取整叠", _withdraw.bind(true)))
	_note = Label.new()
	column.add_child(_note)
	_retry = _button("重试保存", func() -> void: retry_save_requested.emit())
	column.add_child(_retry)
	column.add_child(_button("移动 / 拆除", func() -> void: manage_requested.emit()))
	column.add_child(_button("关闭 [Esc]", set_open.bind(false)))
	hide()


func _list(parent: Node) -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(140, 64)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(12, 12)
	parent.add_child(list)
	return list


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func set_open(value: bool) -> void:
	var was_open: bool = visible
	_set_modal_open(value)
	if was_open and not visible: closed.emit()


func render(snapshot: Dictionary) -> void:
	if _note == null: return
	_fill(_bag, _bag_ids, snapshot.get("bag", []))
	_fill(_storage, _storage_ids, snapshot.get("storage", []))
	_note.text = snapshot.get("message", "")
	_retry.visible = snapshot.get("save_pending", false)
	if snapshot.get("save_pending", false): _note.text = "进度尚未保存，请重试保存"


func _fill(list: ItemList, ids: Array[StringName], rows: Array) -> void:
	var chosen: StringName = ids[list.get_selected_items()[0]] if not list.get_selected_items().is_empty() else &""
	list.clear()
	ids.clear()
	for entry: Dictionary in rows:
		ids.append(entry.id)
		list.add_item(entry.text, entry.icon)
		if entry.id == chosen: list.select(ids.size() - 1)
	if list.get_selected_items().is_empty() and list.item_count > 0: list.select(0)


func _deposit(all: bool) -> void:
	if not _bag.get_selected_items().is_empty(): deposit_requested.emit(_bag_ids[_bag.get_selected_items()[0]], all)


func _withdraw(all: bool) -> void:
	if not _storage.get_selected_items().is_empty(): withdraw_requested.emit(_storage_ids[_storage.get_selected_items()[0]], all)


func _input(event: InputEvent) -> void:
	if visible and not event.is_echo() and event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
