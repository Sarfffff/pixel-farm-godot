extends Control
## 睡前结算：显示第几天、今日收获与收入，确认后进入第二天并自动存档。
##
## 打开时锁玩家输入、收起工具栏，与其他面板互斥。

@onready var _title: Label = %Title
@onready var _lines: Label = %Lines
@onready var _sleep_button: Button = %SleepButton
@onready var _overlay: ColorRect = $Overlay
var _forced: bool = false


func _ready() -> void:
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_sleep_button.pressed.connect(_sleep)
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		time.day_over.connect(_on_day_over)
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_sleep()
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if not open and _forced:
		return
	visible = open
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(open)
	var toolbar := get_node_or_null("../Toolbar")
	if toolbar != null and toolbar.has_method(&"set_ui_visible"):
		toolbar.set_ui_visible(not open)
	if not open:
		return
	for panel_name: String in ["DialoguePanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
		var panel := get_node_or_null("../%s" % panel_name) as Control
		if panel != null and panel.visible:
			panel.set_open(false)
	var bag := get_node_or_null("../InventoryPanel") as Control
	if bag != null and bag.visible:
		bag.call(&"set_open", false)
	var shop := get_node_or_null("../ShopPanel") as Control
	if shop != null and shop.visible:
		shop.call(&"set_open", false)
	_refresh()


func _refresh() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var day: int = time.day if time != null else 1
	var income: int = economy.today_income if economy != null else 0
	var coins: int = economy.coins if economy != null else 0
	var collected: int = inventory.today_collected if inventory != null else 0
	_title.text = "第 %d 天结束" % day
	_lines.text = "今日收获 %d 件 · 今日收入 %d 金币\n金币余额 %d\n\n明天是第 %d 天，作物会按浇水情况生长一阶。" % [
		collected, income, coins, day + 1,
	]
	var activities: Node = get_tree().get_first_node_in_group(&"farm_activities")
	if activities != null:
		_lines.text = "今日收获 %d 件 · 今日收入 %d 金币\n金币余额 %d\n\n%s" % [collected, income, coins, activities.tomorrow_text()]


## 睡觉：推进一天（作物结算）、关面板、自动存档。
func _sleep() -> void:
	_forced = false
	set_open(false)
	var time := get_tree().get_first_node_in_group(&"time")
	if time == null or not time.has_method(&"sleep"):
		return
	time.sleep()
	var save := get_tree().get_first_node_in_group(&"save")
	if save != null and save.has_method(&"save_game"):
		save.save_game()


func _on_day_over() -> void:
	_forced = true
	set_open(true)
	_title.text = "夜深了 · 该休息了"


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
