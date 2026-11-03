extends Label
## 入包提示：在工具栏上方浮出「+N 物品」，轻微上升后淡出。
##
## 订阅 inventory 的 item_added 信号，任何来源（砍树、拾取、购买）都能复用。

const HOLD: float = 0.8
const FADE: float = 0.3
const RISE: float = 6.0

var _tween: Tween
var _base_y: float


func _ready() -> void:
	_base_y = position.y
	get_viewport().size_changed.connect(_update_position)
	_update_position()
	modulate.a = 0.0
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory != null and inventory.has_signal(&"item_added"):
		inventory.item_added.connect(_on_item_added)


func _update_position() -> void:
	# 与快捷栏一起锚定底部，不随基础视口变化跑到屏幕左上。
	_base_y = get_viewport_rect().size.y - 79.0
	position = Vector2(roundf((get_viewport_rect().size.x - size.x) * 0.5), _base_y)


## 立刻收起当前提示（打开背包等面板时调用，避免飘字压住面板）。
func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0


func show_message(message: String) -> void:
	text = message
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	position.y = _base_y
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.1)
	_tween.parallel().tween_property(self, "position:y", _base_y - RISE, HOLD + FADE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, FADE).set_delay(HOLD)


func _on_item_added(id: StringName, count: int) -> void:
	# 背包面板本身就开着时不要再飘字，否则会压在面板中央。
	var panel := get_parent().get_node_or_null("InventoryPanel") as Control
	if panel != null and panel.visible:
		return
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	if inventory == null:
		return
	var definition: ItemData = inventory.definition(id)
	var label: String = definition.display_name if definition != null else String(id)
	show_message("+%d %s" % [count, label])
