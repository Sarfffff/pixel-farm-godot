extends Control
## 木箱与钓鱼共用小面板；走现有玩家输入锁，时间随之暂停。

var manager: Node
var mode: StringName = &"storage"
var title: Label
var note: Label
var bag: ItemList
var chest: ItemList
var bag_ids: Array[StringName] = []
var chest_ids: Array[StringName] = []
var lists: HBoxContainer
var transfer_bar: HBoxContainer
var fish_box: VBoxContainer
var fish_status: Label
var fish_progress: ProgressBar
var fish_button: Button
var _frame: PanelContainer
var _overlay: ColorRect


func _ready() -> void:
	add_to_group(&"modal_ui")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	var skin: Theme = Theme.new()
	skin.default_font = font
	skin.default_font_size = 7
	for type: String in ["Label", "Button", "ItemList"]:
		skin.set_color("font_color", type, Color("514c40"))
		skin.set_color("font_selected_color", type, Color("514c40"))
		skin.set_color("font_hover_color", type, Color("514c40"))
		skin.set_color("font_pressed_color", type, Color("514c40"))
		skin.set_color("font_focus_color", type, Color("514c40"))
	var list_style: StyleBoxFlat = StyleBoxFlat.new()
	list_style.bg_color = Color("eee3c2")
	list_style.border_color = Color("a98b68")
	list_style.set_border_width_all(1)
	skin.set_stylebox("panel", "ItemList", list_style)
	var selected: StyleBoxFlat = list_style.duplicate() as StyleBoxFlat
	selected.bg_color = Color("cad698")
	skin.set_stylebox("selected", "ItemList", selected)
	skin.set_stylebox("selected_focus", "ItemList", selected)
	var button_style: StyleBoxFlat = list_style.duplicate() as StyleBoxFlat
	button_style.bg_color = Color("d0ad7e")
	button_style.content_margin_left = 4
	button_style.content_margin_right = 4
	button_style.content_margin_top = 2
	button_style.content_margin_bottom = 2
	skin.set_stylebox("normal", "Button", button_style)
	var hover: StyleBoxFlat = button_style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("cad698")
	skin.set_stylebox("hover", "Button", hover)
	skin.set_stylebox("pressed", "Button", hover)
	theme = skin
	var overlay: ColorRect = ColorRect.new()
	_overlay = overlay
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.05, 0.07, 0.06, 0.5)
	overlay.gui_input.connect(_on_overlay_input)
	add_child(overlay)
	var frame: PanelContainer = PanelContainer.new()
	_frame = frame
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -142
	frame.offset_right = 142
	frame.offset_top = -76
	frame.offset_bottom = 76
	frame.custom_minimum_size = Vector2(284, 152)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("eee3c2")
	style.border_color = Color("8e6b4c")
	style.set_border_width_all(2)
	style.shadow_color = Color(0.1, 0.1, 0.05, 0.3)
	style.shadow_size = 2
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 10)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	frame.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	column.add_child(heading)
	title = _label("农场木箱", 9)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	heading.add_child(_button("关闭 [Esc]", close))
	note = _label("选中物品后存取；支持整叠搬运。", 6)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	lists = HBoxContainer.new()
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lists)
	bag = _list_column(lists, "随身背包")
	chest = _list_column(lists, "木箱 · 24 格")
	transfer_bar = HBoxContainer.new()
	transfer_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(transfer_bar)
	transfer_bar.add_child(_button("存 1 →", _deposit.bind(false)))
	transfer_bar.add_child(_button("存整叠 →", _deposit.bind(true)))
	transfer_bar.add_child(_button("← 取 1", _withdraw.bind(false)))
	transfer_bar.add_child(_button("← 取整叠", _withdraw.bind(true)))
	fish_box = VBoxContainer.new()
	fish_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(fish_box)
	fish_status = _label("", 9)
	fish_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fish_status.custom_minimum_size = Vector2(190, 35)
	fish_box.add_child(fish_status)
	fish_progress = ProgressBar.new()
	fish_progress.custom_minimum_size = Vector2(190, 8)
	fish_progress.show_percentage = false
	var track: StyleBoxFlat = list_style.duplicate() as StyleBoxFlat
	track.bg_color = Color("c2b18c")
	var fill: StyleBoxFlat = selected.duplicate() as StyleBoxFlat
	fill.bg_color = Color("8eac70")
	fish_progress.add_theme_stylebox_override("background", track)
	fish_progress.add_theme_stylebox_override("fill", fill)
	fish_box.add_child(fish_progress)
	fish_button = _button("投竿 [E / 空格]", _fish_action)
	fish_box.add_child(fish_button)
	var instructions: Label = _label("看到咬钩提示再收杆；等待时提前按键不会钓到鱼。", 6)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fish_box.add_child(instructions)
	manager.changed.connect(refresh)
	manager.inventory.changed.connect(refresh)
	hide()


func _label(text: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 7)
	button.pressed.connect(callback)
	return button


func _list_column(parent: HBoxContainer, text: String) -> ItemList:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label(text, 7))
	var list: ItemList = ItemList.new()
	list.custom_minimum_size = Vector2(120, 64)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(12, 12)
	list.icon_mode = ItemList.ICON_MODE_LEFT
	list.add_theme_font_size_override("font_size", 7)
	column.add_child(list)
	parent.add_child(column)
	return list


func open(next_mode: StringName) -> void:
	mode = next_mode
	manager.message = ""
	for sibling: Node in get_parent().get_children():
		if sibling != self and sibling is Control and sibling.visible and sibling.has_method(&"set_open"):
			sibling.set_open(false)
	show()
	var toast: Node = get_parent().get_node_or_null("Toast")
	if toast != null: toast.clear()
	manager.player.set_input_locked(true)
	_set_toolbar(false)
	refresh()
	if mode == &"storage":
		bag.grab_focus()
	else:
		fish_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	if mode == &"fishing":
		manager.cancel_fishing()
	manager.player.set_input_locked(false)
	_set_toolbar(not manager.player.input_locked)


func _set_toolbar(shown: bool) -> void:
	var toolbar: Node = get_parent().get_node_or_null("Toolbar")
	if toolbar != null:
		toolbar.set_ui_visible(shown)


func _process(_delta: float) -> void:
	if not visible:
		return
	for sibling: Node in get_parent().get_children():
		if sibling != self and sibling is Control and sibling.visible and sibling.has_method(&"set_open"):
			close()
			return
	if mode == &"fishing":
		_refresh_fishing()


func _input(event: InputEvent) -> void:
	if not visible or event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"toggle_inventory"):
		close()
		get_viewport().set_input_as_handled()
	elif mode == &"fishing" and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"use_tool") or event.is_action_pressed(&"ui_accept")):
		_fish_action()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if title == null or not visible:
		return
	var storage_mode: bool = mode == &"storage"
	_overlay.color.a = 0.5 if storage_mode else 0.2
	lists.visible = storage_mode
	transfer_bar.visible = storage_mode
	fish_box.visible = not storage_mode
	_frame.custom_minimum_size = Vector2.ZERO
	_frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER if storage_mode else Control.PRESET_CENTER_RIGHT)
	_frame.offset_left = -150 if storage_mode else -236
	_frame.offset_right = 150 if storage_mode else -8
	_frame.offset_top = -82
	_frame.offset_bottom = 82
	title.text = "木箱 · 24 格仓库" if storage_mode else "池塘钓鱼"
	if not storage_mode:
		_refresh_fishing()
		return
	var selected_bag: int = bag.get_selected_items()[0] if not bag.get_selected_items().is_empty() else 0
	var selected_chest: int = chest.get_selected_items()[0] if not chest.get_selected_items().is_empty() else 0
	bag.clear()
	chest.clear()
	bag_ids.clear()
	chest_ids.clear()
	for item: ItemData in manager.inventory.definitions():
		var owned: int = manager.inventory.count_of(item.id)
		if owned > 0 and item.category != &"tool":
			bag.add_item("%s ×%d" % [item.display_name, owned], item.icon)
			bag_ids.append(item.id)
		var stored: int = manager.storage.count_of(item.id)
		if stored > 0:
			chest.add_item("%s ×%d" % [item.display_name, stored], item.icon)
			chest_ids.append(item.id)
	if bag.item_count > 0:
		bag.select(mini(selected_bag, bag.item_count - 1))
	if chest.item_count > 0:
		chest.select(mini(selected_chest, chest.item_count - 1))
	note.text = manager.message if not manager.message.is_empty() else "选中物品后存取；箱满/包满时保留放不下的部分。"


func _deposit(all: bool) -> void:
	if bag.get_selected_items().is_empty():
		return
	var id: StringName = bag_ids[bag.get_selected_items()[0]]
	manager.deposit(id, mini(manager.inventory.definition(id).max_stack, manager.inventory.count_of(id)) if all else 1)


func _withdraw(all: bool) -> void:
	if chest.get_selected_items().is_empty():
		return
	var id: StringName = chest_ids[chest.get_selected_items()[0]]
	manager.withdraw(id, mini(manager.inventory.definition(id).max_stack, manager.storage.count_of(id)) if all else 1)


func _fish_action() -> void:
	manager.fishing_action()
	refresh()


func _refresh_fishing() -> void:
	note.text = "每日投竿 %d/%d · 消耗体力 %d · 可按 Esc 结束" % [manager.casts_today, manager.settings.fishing_limit, manager.settings.fishing_cost]
	fish_status.text = manager.fishing_text()
	fish_progress.value = manager.fishing_progress() * 100.0
	fish_button.text = "收杆！ [E / 空格]" if manager.fishing_state == &"bite" else "等待咬钩…" if manager.fishing_state == &"waiting" else "领取鱼获" if manager.pending_fish != &"" else "投竿 [E / 空格]"


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()
