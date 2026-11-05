extends "res://scripts/ui/common/modal_panel.gd"
## 订单箱面板：显示今天的订单与进度，材料够了就能交付。

@onready var _icon: TextureRect = %ItemIcon
@onready var _item_name: Label = %ItemName
@onready var _progress: Label = %ItemProgress
@onready var _reward: Label = %Reward
@onready var _message: Label = %Message
@onready var _deliver: Button = %DeliverButton
@onready var _overlay: ColorRect = $Overlay


func _ready() -> void:
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_deliver.pressed.connect(_on_deliver_pressed)
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact"):
		if not _deliver.disabled:
			_on_deliver_pressed()
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	_set_modal_open(open)
	if not open:
		return
	_refresh()


func _refresh() -> void:
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders == null or not orders.has_method(&"has_order"):
		_show_empty("订单系统没准备好")
		return
	if not orders.has_order():
		_show_empty("今天的订单已经交付完了\n明天再来看看")
		return
	var order: Dictionary = orders.order
	_icon.texture = order.get(&"icon", null)
	_item_name.text = String(order.get(&"name", "货物"))
	_progress.text = "%d / %d" % [int(orders.owned()), int(orders.required())]
	_reward.text = "报酬 %d 金币 · 含今天剩 %d 天" % [int(orders.reward()), int(orders.days_left())]
	_deliver.disabled = not orders.can_deliver()
	_deliver.text = "交付" if not _deliver.disabled else "货物不够"
	_message.text = "" if _deliver.disabled else "按 F 或点按钮交付"


func _show_empty(text: String) -> void:
	_icon.texture = null
	_item_name.text = "—"
	_progress.text = ""
	_reward.text = ""
	_deliver.disabled = true
	_deliver.text = "交付"
	_message.text = text


func _on_deliver_pressed() -> void:
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders == null or not orders.has_method(&"deliver"):
		return
	var paid: int = int(orders.reward())
	if not orders.deliver():
		_message.text = "材料不够，先去收点货"
		return
	_refresh()
	_message.text = "交付完成，+%d 金币" % paid


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
