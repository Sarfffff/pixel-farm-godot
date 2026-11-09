extends PanelContainer
## 八格快捷栏只引用背包物品，与背包共用 ItemSlot，不复制库存。

const ItemSlot := preload("res://scripts/ui/common/item_slot.gd")
const SLOT_NAMES: Array[String] = ["Hoe", "WateringCan", "Seeds", "Axe", "StonePickaxe", "Slot6", "Slot7", "Slot8"]
const TIP_TEXT_WIDTH: float = 180.0
var _inventory: Inventory
var _player: CharacterBody2D
var _hint: Label
var _hint_panel: PanelContainer
var _tip: Label
var _tip_panel: PanelContainer
var _tip_tween: Tween
var _tool_name: Label


func _ready() -> void:
	_inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	_player = get_node_or_null("../../Farm/World/Player") as CharacterBody2D
	_build_ui()
	if _inventory == null:
		return
	for index in Inventory.HOTBAR_SIZE:
		var slot := ItemSlot.new()
		slot.name = SLOT_NAMES[index]
		slot.inventory = _inventory
		slot.hotbar_index = index
		slot.view_index = index
		slot.selected.connect(_on_slot_selected)
		$Slots.add_child(slot)
	_inventory.changed.connect(_refresh)
	_inventory.hotbar_changed.connect(_refresh)
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades != null:
		upgrades.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _inventory == null or _inventory.hotbar.size() != Inventory.HOTBAR_SIZE:
		return
	for index in Inventory.HOTBAR_SIZE:
		var slot := _slot(index)
		if slot == null:
			continue
		slot.item_id = _inventory.hotbar[index]
		slot.is_selected = index == _inventory.active_slot
		slot.refresh()
	_tool_name.text = _inventory.item_name(_inventory.active_item())


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player) or _inventory == null:
		return
	_tool_name.visible = visible
	_tool_name.position = Vector2(roundf((get_viewport_rect().size.x - _tool_name.size.x) * 0.5), get_global_rect().end.y + 1)
	var ambient: String = _player.nearby_hint()
	var tiller: Node = _player.interaction if is_instance_valid(_player.interaction) else null
	if tiller != null and tiller.has_harvest_target():
		ambient = "[F] 收获成熟作物"
	var text: String = ambient
	if text.is_empty():
		if tiller != null and _player.current_tool != &"none":
			text = "%s · %s" % [_inventory.item_name(_inventory.active_item()), tiller.interaction_hint(_player.current_tool)]
		else:
			text = "[B] 背包 · 拖拽物品或按 1–8 绑定快捷位"
	_hint.text = text
	_hint_panel.visible = visible and not text.is_empty() and not _tip_panel.visible
	_hint_panel.reset_size()
	_hint_panel.position = Vector2(roundf((get_viewport_rect().size.x - _hint_panel.size.x) * 0.5), get_global_rect().position.y - _hint_panel.size.y - 4)


func _on_slot_selected(index: int) -> void:
	if _player != null:
		_player._select_hotbar(index)
	_show_tip(index)


func _slot(index: int) -> Panel:
	return $Slots.get_child(index) as Panel if index >= 0 and index < $Slots.get_child_count() else null


func set_ui_visible(shown: bool) -> void:
	# 场景退出时面板可能仍在收尾关闭；此时不能再查询模态组。
	if not is_inside_tree():
		return
	var modals := get_tree().get_first_node_in_group(&"modal_coordinator")
	if shown and modals != null and modals.has_open_panel():
		shown = false
	visible = shown
	_tool_name.visible = shown
	_hint_panel.visible = shown and not _hint.text.is_empty()
	_tip_panel.hide()
	var hud := get_node_or_null("../HUD")
	if hud != null:
		hud.set_ui_visible(shown)


func _show_tip(index: int) -> void:
	var id: StringName = _inventory.hotbar[index]
	var item: ItemData = _inventory.definition(id)
	_tip.text = "%s · %s" % [_inventory.item_name(id), item.description] if item != null else "空快捷位 · 打开背包，拖入物品或按数字绑定"
	_tip_panel.reset_size()
	_position_tip()
	_tip_panel.show()
	_tip_panel.modulate.a = 1.0
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = create_tween()
	_tip_tween.tween_interval(3.0)
	_tip_tween.tween_property(_tip_panel, "modulate:a", 0.0, 0.25)
	_tip_tween.tween_callback(_tip_panel.hide)


func _position_tip() -> void:
	_tip_panel.position = Vector2(roundf((get_viewport_rect().size.x - _tip_panel.size.x) * 0.5), get_global_rect().position.y - _tip_panel.size.y - 4)


func _label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", get_theme_font("font"))
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color("4b3527"))
	return label


func _build_ui() -> void:
	_hint = _label()
	_hint_panel = _wrap(_hint)
	_tip = _label()
	# 隐藏的Label尚未经过Container布局，先给定换行宽度，避免首次按零宽逐字计算高度。
	_tip.custom_minimum_size.x = TIP_TEXT_WIDTH
	_tip.size.x = TIP_TEXT_WIDTH
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_panel = _wrap(_tip)
	_tip_panel.resized.connect(_position_tip)
	_tool_name = _label()
	_tool_name.add_theme_color_override("font_color", Color("fff1d0"))
	_tool_name.add_theme_color_override("font_outline_color", Color("47334f"))
	_tool_name.add_theme_constant_override("outline_size", 1)
	get_parent().add_child.call_deferred(_tool_name)


func _wrap(label: Label) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.hide()
	get_parent().add_child.call_deferred(panel)
	return panel
