extends "res://scripts/ui/common/modal_panel.gd"

## 黑屏后、跨天保存前，由组合根决定异地累倒的返回位置。
signal pass_out_relocating
## 睡前结算：显示第几天、今日收获与收入，确认后进入第二天并自动存档。
##
## 打开时锁玩家输入、收起工具栏，与其他面板互斥。

@onready var _title: Label = %Title
@onready var _lines: Label = %Lines
@onready var _sleep_button: Button = %SleepButton
@onready var _overlay: ColorRect = $Overlay
## 累倒流程进行中，避免同一晚触发两次
var _passing_out: bool = false


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
	_set_modal_open(open)
	if not open:
		return
	_refresh()


func _refresh() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	var economy := get_tree().get_first_node_in_group(&"economy") as Economy
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var day: int = time.day if time != null else 1
	var income: int = economy.today_income if economy != null else 0
	var coins: int = economy.coins if economy != null else 0
	var collected: int = inventory.today_collected if inventory != null else 0
	# 白天上床只是小睡到傍晚，晚上上床才算过完这一天。
	var night: bool = true
	if time != null and time.has_method(&"is_evening"):
		night = bool(time.call(&"is_evening"))
	var clock: String = ""
	if time != null and time.has_method(&"clock_text"):
		clock = String(time.call(&"clock_text"))

	if night:
		_title.text = "第 %d 天结束" % day
		_sleep_button.text = "睡觉 · 进入第 %d 天" % (day + 1)
	else:
		_title.text = "第 %d 天 · %s 还没到晚上" % [day, clock]
		_sleep_button.text = "小睡到 20:00"

	var headline := "今日收获 %d 件 · 今日收入 %d 金币\n金币余额 %d" % [collected, income, coins]
	var tail := ""
	if not night:
		tail = "现在 %s，睡一觉到 20:00；晚上再睡才算过完这一天。" % clock
	else:
		var activities: Node = get_tree().get_first_node_in_group(&"farm_activities")
		if activities != null:
			tail = String(activities.tomorrow_text())
		else:
			tail = "明天是第 %d 天，作物会按浇水情况生长一阶。" % (day + 1)
	_lines.text = "%s\n\n%s" % [headline, tail]


## 睡觉：渐黑 → 角色躺下 → 推进一天 → 存档 → 天亮在床边醒来。
## 过程中要等黑屏与停留，所以是异步的；按钮回调直接 await 即可。
func _sleep() -> void:
	_play_sleep_sfx()
	set_open(false)

	# set_open(false) 会解锁输入，这里立刻锁回去：黑屏期间不许走动。
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(true)

	var house := get_tree().get_first_node_in_group(&"house")
	var fade := get_tree().get_first_node_in_group(&"screen_fade")
	var time := get_tree().get_first_node_in_group(&"time")

	# 白天小睡到傍晚，18:00 之后上床才算过完这一天。
	var night: bool = true
	if time != null and time.has_method(&"is_evening"):
		night = bool(time.call(&"is_evening"))

	if fade != null:
		await fade.call(&"fade_out", 0.45)
	if house != null and house.has_method(&"begin_sleep"):
		house.call(&"begin_sleep")
	if fade != null:
		fade.call(&"show_caption", "晚安 · 第 %d 天" % _day() if night else "小睡一会儿")

	if time == null:
		return
	var advanced: bool = true
	if time.has_method(&"rest"):
		advanced = bool(time.call(&"rest"))
	elif time.has_method(&"sleep"):
		time.call(&"sleep")
	else:
		return

	if advanced:
		var save := get_tree().get_first_node_in_group(&"save")
		if save != null and save.has_method(&"save_game"):
			save.save_game()
		if fade != null:
			fade.call(&"show_caption", "第 %d 天 · 早上好" % _day())
	else:
		var clock := ""
		if time.has_method(&"clock_text"):
			clock = String(time.call(&"clock_text"))
		if fade != null:
			fade.call(&"show_caption", "醒来 · 第 %d 天 %s" % [_day(), clock])

	await get_tree().create_timer(0.9).timeout
	if fade != null:
		fade.call(&"hide_caption")

	if house != null and house.has_method(&"finish_sleep"):
		await house.call(&"finish_sleep")
		return
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(false)
	if fade != null:
		await fade.call(&"fade_in", 0.5)


func _day() -> int:
	var time := get_tree().get_first_node_in_group(&"time")
	return int(time.day) if time != null else 1


func _play_sleep_sfx() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call(&"play_sfx", &"sleep")


## 凌晨 2:00 累倒（星露谷规则）：不弹面板，直接黑屏 → 罚款 → 进下一天 →
## 体力只回一半 → 在床边（室外则在农舍门口）醒来 → 自动存档。
func _on_day_over() -> void:
	if _passing_out:
		return
	_passing_out = true
	await _pass_out()
	_passing_out = false


func _pass_out() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	var house := get_tree().get_first_node_in_group(&"house")
	var fade := get_tree().get_first_node_in_group(&"screen_fade")
	var time := get_tree().get_first_node_in_group(&"time")
	var economy := get_tree().get_first_node_in_group(&"economy")
	var stamina := get_tree().get_first_node_in_group(&"stamina")
	var indoors: bool = house != null and bool(house.call(&"is_inside"))

	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(true)

	var lost: int = 0
	if economy != null and economy.has_method(&"pass_out_fine"):
		lost = int(economy.call(&"pass_out_fine"))

	if fade != null:
		await fade.call(&"fade_out", 0.6)
	pass_out_relocating.emit()
	if indoors:
		house.call(&"begin_sleep")
	if fade != null:
		fade.call(&"show_caption", "凌晨两点，你累倒了……")

	if time != null and time.has_method(&"sleep"):
		time.call(&"sleep")
	# day_started 会把体力回满，这里再压回一半
	if stamina != null and stamina.has_method(&"wake_weary"):
		stamina.call(&"wake_weary")

	var save := get_tree().get_first_node_in_group(&"save")
	if save != null and save.has_method(&"save_game"):
		save.save_game()

	await get_tree().create_timer(1.0).timeout
	if not indoors:
		# 室外累倒：被人送回农舍门口
		var door := get_tree().current_scene.get_node_or_null("Farm/World/CottageDoor") as Node2D
		if door != null and player != null:
			player.global_position = door.global_position + Vector2(0, 16)
	if house != null and house.has_method(&"finish_sleep"):
		await house.call(&"finish_sleep")
		if not indoors and player != null and player.has_method(&"set_input_locked"):
			player.set_input_locked(false)
	elif fade != null:
		if fade.has_method(&"hide_caption"):
			fade.call(&"hide_caption")
		await fade.call(&"fade_in", 0.5)
		if player != null and player.has_method(&"set_input_locked"):
			player.set_input_locked(false)

	if fade != null and lost > 0 and fade.has_method(&"show_caption"):
		fade.call(&"show_caption", "第 %d 天 · 早上好（被罚走 %d 金币）" % [_day(), lost])
		await get_tree().create_timer(1.4).timeout
		fade.call(&"hide_caption")


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
