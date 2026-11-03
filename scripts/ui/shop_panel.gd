extends Control
## 农场商店：左边买种子、右边卖背包里的货，底部显示当前金币与最近一笔交易。
##
## 数据全部来自物品表（`buy_price > 0` 可买、`sell_price > 0` 可卖），加物品不用改这里。
## 打开时锁玩家输入并收起工具栏；Esc / 点空白关闭。

const MAX_BUY_PER_CLICK: int = 99
signal item_sold(id: StringName, count: int)

@onready var _buy_list: VBoxContainer = %BuyList
@onready var _sell_list: VBoxContainer = %SellList
@onready var _coins: Label = %Coins
@onready var _message: Label = %Message
@onready var _overlay: ColorRect = $Overlay
@onready var _upgrade_button: Button = %UpgradeButton

var _inventory: Inventory
var _economy: Economy
## 行的显示数据：{ id, buy, price, name }
var _rows: Array[Dictionary] = []
var _row_nodes: Array[Panel] = []
var _selected: int = 0
var _idle_style: StyleBoxTexture
var _active_style: StyleBoxTexture
var _font: Font


func _ready() -> void:
	_idle_style = get_theme_stylebox("idle", "InventorySlot") as StyleBoxTexture
	_active_style = get_theme_stylebox("selected", "InventorySlot") as StyleBoxTexture
	_font = get_theme_font("font")
	_inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	_economy = get_tree().get_first_node_in_group(&"economy") as Economy
	if _inventory == null or _economy == null:
		push_error("[shop_panel] 缺少 inventory 或 economy 节点，商店不可用")
		hide()
		return
	_economy.changed.connect(_on_coins_changed)
	_inventory.changed.connect(_rebuild)
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_upgrade_button.pressed.connect(_purchase_upgrade)
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades != null:
		upgrades.changed.connect(_refresh_upgrade)
	hide()


func _input(event: InputEvent) -> void:
	if _inventory == null:
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		_select(_selected - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_select(_selected + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"use_tool"):
		_trade(_selected, Input.is_key_pressed(KEY_SHIFT))
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	visible = open
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(open)
	var toolbar := get_node_or_null("../Toolbar")
	if toolbar != null and toolbar.has_method(&"set_ui_visible"):
		toolbar.set_ui_visible(not open)
	if not open:
		return
	# 与背包/对话互斥：打开商店时收起它们，避免多个面板叠在一起抢输入。
	var bag := get_node_or_null("../InventoryPanel") as Control
	if bag != null and bag.visible:
		bag.call(&"set_open", false)
	for other_name: String in ["DialoguePanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
		var other := get_node_or_null("../%s" % other_name) as Control
		if other != null and other.visible:
			other.call(&"set_open", false)
	_rebuild()


func _rebuild() -> void:
	if _inventory == null or not visible:
		return
	for child in _buy_list.get_children():
		child.queue_free()
	for child in _sell_list.get_children():
		child.queue_free()
	_rows.clear()
	_row_nodes.clear()

	var offers := _inventory.definitions()
	# 商店只卖"社区中心阶段够"的货，剩下的挂在列表末尾提示玩家去修。
	var unlocked: int = 0
	var community := get_tree().get_first_node_in_group(&"community")
	if community != null and community.has_method(&"unlocked_stage"):
		unlocked = int(community.unlocked_stage())
	var locked: int = 0
	for item: ItemData in offers:
		if item.buy_price <= 0:
			continue
		if item.unlock_stage <= unlocked:
			_add_row(_buy_list, item, true, item.buy_price, _inventory.count_of(item.id))
		else:
			locked += 1
	if locked > 0:
		_add_locked_hint(locked)
	for item: ItemData in offers:
		var owned: int = _inventory.count_of(item.id)
		if item.sell_price > 0 and owned > 0:
			_add_row(_sell_list, item, false, item.sell_price, owned)

	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "背包里没有可卖的物品"
		empty.add_theme_font_override("font", _font)
		empty.add_theme_font_size_override("font_size", 7)
		empty.add_theme_color_override("font_color", Color("d8cba6"))
		_sell_list.add_child(empty)
	_selected = clampi(_selected, 0, maxi(_rows.size() - 1, 0))
	_apply_styles()
	_refresh_upgrade()


func _add_row(parent: VBoxContainer, item: ItemData, buy: bool, price: int, owned: int) -> void:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(84, 18)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _idle_style != null:
		row.add_theme_stylebox_override("panel", _idle_style)

	var icon := TextureRect.new()
	icon.position = Vector2(1, 1)
	icon.size = Vector2(16, 16)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture = item.icon
	row.add_child(icon)

	var name_label := Label.new()
	name_label.position = Vector2(19, 1)
	name_label.size = Vector2(44, 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color("eee4c3"))
	name_label.text = item.display_name
	row.add_child(name_label)

	var price_label := Label.new()
	price_label.position = Vector2(56, 1)
	price_label.size = Vector2(27, 16)
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_override("font", _font)
	price_label.add_theme_font_size_override("font_size", 7)
	price_label.add_theme_color_override("font_color", Color("f0d68c"))
	price_label.text = str(price) if buy else "%d×%d" % [price, owned]
	row.add_child(price_label)

	var index: int = _rows.size()
	_rows.append({&"id": item.id, &"buy": buy, &"price": price, &"name": item.display_name})
	_row_nodes.append(row)
	row.gui_input.connect(_on_row_gui_input.bind(index))
	parent.add_child(row)


## 买入列表末尾的一行灰字：还有几种种子没解锁，去修社区中心。
func _add_locked_hint(locked: int) -> void:
	var hint := Label.new()
	hint.text = "还有 %d 种货没解锁\n去社区中心看看" % locked
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 6)
	hint.add_theme_color_override("font_color", Color("8e8472"))
	_buy_list.add_child(hint)


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected = index
	_apply_styles()
	_trade(index, Input.is_key_pressed(KEY_SHIFT))


func _select(index: int) -> void:
	if _rows.is_empty():
		return
	_selected = clampi(index, 0, _rows.size() - 1)
	_apply_styles()


func _apply_styles() -> void:
	for index in _row_nodes.size():
		var style: StyleBox = _active_style if index == _selected else _idle_style
		if style != null:
			_row_nodes[index].add_theme_stylebox_override("panel", style)


## 一笔交易：买就扣钱加物品，卖就减物品加钱；拿不到货时不改任何数值。
func _trade(index: int, all: bool) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	var id: StringName = row[&"id"]
	var price: int = row[&"price"]
	var name: String = row[&"name"]
	if bool(row[&"buy"]):
		var item: ItemData = _inventory.definition(id)
		if item != null and item.category == &"tool" and _inventory.count_of(id) > 0:
			_set_message("已拥有%s，无需重复购买" % name)
			return
		var wanted: int = MAX_BUY_PER_CLICK if all else 1
		var bought: int = _buy(id, price, wanted)
		if bought <= 0:
			_set_message("金币不足或背包已满")
			return
		_set_message("买入 %s ×%d（-%d）" % [name, bought, price * bought])
	else:
		var owned: int = _inventory.count_of(id)
		var wanted: int = owned if all else 1
		var sold: int = _sell(id, price, wanted)
		if sold <= 0:
			_set_message("没有可卖的 %s" % name)
			return
		_set_message("卖出 %s ×%d（+%d）" % [name, sold, price * sold])
	_rebuild()


func _buy(id: StringName, price: int, wanted: int) -> int:
	var bought: int = 0
	for step in mini(wanted, MAX_BUY_PER_CLICK):
		var item: ItemData = _inventory.definition(id)
		if item != null and item.category == &"tool" and _inventory.count_of(id) > 0:
			break
		if not _economy.can_afford(price):
			break
		if _inventory.add_item(id, 1) > 0:
			break
		_economy.spend(price)
		bought += 1
	return bought


func _sell(id: StringName, price: int, wanted: int) -> int:
	var count: int = mini(wanted, _inventory.count_of(id))
	if count <= 0 or not _inventory.remove_item(id, count):
		return 0
	_economy.earn(price * count)
	item_sold.emit(id, count)
	return count


func _on_coins_changed(coins: int) -> void:
	if _coins != null:
		_coins.text = str(coins)
	_refresh_upgrade()


func _refresh_upgrade() -> void:
	if not is_instance_valid(_upgrade_button):
		return
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades == null:
		_upgrade_button.disabled = true
		return
	if upgrades.watering_level > 0:
		_upgrade_button.text = "铜水壶已升级 · 一次三格 / 体力 3"
		_upgrade_button.disabled = true
		return
	var config: Resource = upgrades.WATERING
	_upgrade_button.text = "升级铜水壶 · %d 金 / 木%d / 石%d" % [config.coin_cost, config.wood_cost, config.stone_cost]
	_upgrade_button.disabled = false


func _purchase_upgrade() -> void:
	var upgrades := get_tree().get_first_node_in_group(&"upgrades")
	if upgrades == null:
		return
	if upgrades.purchase():
		_set_message("升级完成！水壶一次浇三格，消耗 3 体力")
	else:
		var config: Resource = upgrades.WATERING
		_set_message("需要 %d/%d 金 · 木材 %d/%d · 石头 %d/%d" % [
			_economy.coins, config.coin_cost, _inventory.count_of(&"wood"), config.wood_cost,
			_inventory.count_of(&"stone"), config.stone_cost])
	_refresh_upgrade()


func _set_message(text: String) -> void:
	if _message != null:
		_message.text = text


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
