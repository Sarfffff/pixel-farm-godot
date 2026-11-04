extends SceneTree
## 暂停菜单与标题界面回归：Esc 优先级、暂停/恢复、保存、继续按钮可用性。
## --headless --path . --script res://tools/check/check_pause.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const SLOT_ONE := "user://save_1.json"

var _main: Node2D
var _pause: Control
var _bag: Control
var _save: Node
var _player: CharacterBody2D
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[pause] FAIL: " + message)


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(_main)
	current_scene = _main
	_save = _main.get_node("Systems/Save")
	_save.autoload_enabled = false
	_save.delete_save()
	_pause = _main.get_node("UI/PauseMenu") as Control
	_bag = _main.get_node("UI/InventoryPanel") as Control
	_player = _main.get_node("Farm/World/Player") as CharacterBody2D
	await process_frame
	await process_frame

	_check(_pause != null, "pause menu exists")
	_check(not _pause.visible, "pause menu starts hidden")
	_check(not paused, "tree is not paused at start")
	_check(_pause.can_pause(), "pause allowed when no panel is open")

	# 打开暂停：整个场景树停住、玩家锁输入
	_pause.open()
	await process_frame
	_check(_pause.visible, "pause menu opens")
	_check(paused, "opening pause pauses the tree")
	_check(_player.input_locked, "player locked while paused")

	# 暂停时时间不再前进
	var time := _main.get_node("Systems/Time")
	var minutes_before: int = time.minutes
	await create_timer(0.3, true).timeout
	_check(time.minutes == minutes_before, "clock stops while paused")

	# 关闭后恢复
	_pause.close()
	await process_frame
	_check(not _pause.visible, "pause menu closes")
	_check(not paused, "closing pause resumes the tree")
	_check(not _player.input_locked, "player unlocked after resume")

	# 背包开着时 Esc 归背包处理，不弹暂停
	_bag.call(&"set_open", true)
	_check(not _pause.can_pause(), "panel open blocks the pause menu")
	_bag.call(&"set_open", false)
	_check(_pause.can_pause(), "closing the panel re-enables pause")

	# 保存按钮
	_check(not _save.has_save(), "no save before pressing save")
	_pause.open()
	_pause._save_game()
	_check(_save.has_save(), "pause menu saves the game")
	_check(String(_pause._hint.text).contains("已保存"), "save gives feedback")
	_pause.close()

	# 按键说明：F1 打开、Esc 关闭，打开时暂停游戏树
	var help := _main.get_node_or_null("UI/HelpPanel") as Control
	_check(help != null, "help panel exists")
	if help != null:
		var rows := help.get_node_or_null("Frame/VBox/Rows") as VBoxContainer
		_check(rows != null and rows.get_child_count() >= 6, "help lists the controls")
		_check(help.process_mode == Node.PROCESS_MODE_ALWAYS, "help keeps receiving input while paused")
		help.call(&"set_open", true)
		await process_frame
		_check(help.visible and paused, "help opens and pauses the game")
		_check(not _pause.can_pause(), "help blocks the pause menu")
		help.call(&"set_open", false)
		await process_frame
		_check(not help.visible and not paused, "closing help resumes the game")
		# 暂停菜单里的入口
		_pause.open()
		_check(_pause._items.size() == 6, "pause menu has help and audio entries")
		_pause._on_button_pressed(3)
		await process_frame
		_check(help.visible and not _pause.visible, "help opens from the pause menu")
		help.call(&"set_open", false)
		await process_frame

	# 音乐 / 音效开关
	var audio := root.get_node_or_null("AudioManager")
	_check(audio != null, "AudioManager autoload present")
	if audio != null:
		_pause.open()
		_check(_pause._music_button.text.contains("开"), "music label starts on")
		_pause._on_button_pressed(4)
		_check(not bool(audio.get(&"music_enabled")), "music toggles off")
		_check(_pause._music_button.text.contains("关"), "music label follows")
		_pause._on_button_pressed(4)
		_check(bool(audio.get(&"music_enabled")), "music toggles back on")
		_pause._on_button_pressed(5)
		_check(not bool(audio.get(&"sfx_enabled")), "sfx toggles off")
		_pause._on_button_pressed(5)
		_check(bool(audio.get(&"sfx_enabled")), "sfx toggles back on")
		_pause.close()

	# 标题界面：无档时「继续」置灰，有档时可点
	_save.delete_all()
	var menu := await _spawn_menu()
	var continue_button := menu.get_node("MainFrame/VBox/ContinueButton") as Button
	_check(continue_button.disabled, "continue is disabled without a save")
	menu.queue_free()
	await process_frame

	var file := FileAccess.open(SLOT_ONE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "coins": 10}))
	file.close()
	menu = await _spawn_menu()
	continue_button = menu.get_node("MainFrame/VBox/ContinueButton") as Button
	_check(not continue_button.disabled, "continue is enabled with a save")

	# 「继续」先弹槽位列表：三个槽位、有档可选、空槽置灰
	var slot_frame := menu.get_node("SlotFrame") as Control
	var main_frame := menu.get_node("MainFrame") as Control
	menu.call(&"_open_slots", 0)
	await process_frame
	_check(slot_frame.visible and not main_frame.visible, "continue opens the slot picker")
	var slot_list := menu.get_node("SlotFrame/VBox/SlotList") as VBoxContainer
	_check(slot_list.get_child_count() == 3, "three save slots listed")
	var row_one := slot_list.get_child(0) as HBoxContainer
	_check(not (row_one.get_child(0) as Button).disabled, "slot 1 selectable with a save")
	var row_two := slot_list.get_child(1) as HBoxContainer
	_check((row_two.get_child(0) as Button).disabled, "empty slot disabled in continue mode")
	_check(row_two.get_child_count() == 1, "empty slot has no rename or delete button")
	_check(row_one.get_child_count() == 3, "occupied slot offers rename and delete")

	# 新游戏模式：空槽位也能点，占用槽位提示将覆盖
	menu.call(&"_open_slots", 1)
	await process_frame
	row_one = slot_list.get_child(0) as HBoxContainer
	row_two = slot_list.get_child(1) as HBoxContainer
	_check(not (row_two.get_child(0) as Button).disabled, "new game allows empty slots")
	_check(String((row_one.get_child(0) as Button).text).contains("将覆盖"), "occupied slot warns about overwrite")

	# 新游戏选完槽位先起名，取消则回到槽位列表
	(row_two.get_child(0) as Button).pressed.emit()
	await process_frame
	var name_frame := menu.get_node("NameFrame") as Control
	_check(name_frame.visible and not slot_frame.visible, "new game asks for a farm name")
	menu.call(&"_close_name_entry")
	await process_frame
	_check(not name_frame.visible and slot_frame.visible, "cancel returns to the slot list")

	# 槽位隔离：切到 2 号槽保存，不影响 1 号
	_save.use_slot(2)
	_save.save_name = "河畔农场"
	_check(_save.save_game(), "save into slot 2")
	_check(FileAccess.file_exists(SLOT_ONE), "slot 1 untouched")
	_check(_save.has_save(2), "slot 2 written")
	_check(not _save.has_save(3), "slot 3 still empty")
	_check(String(_save.slot_summary(2).get(&"name", "")) == "河畔农场", "farm name is stored in the save")

	# 改名：只重写 name，不动进度
	menu.call(&"_open_slots", 0)
	await process_frame
	row_one = slot_list.get_child(0) as HBoxContainer
	var rename_button := row_one.get_child(1) as Button
	rename_button.pressed.emit()
	await process_frame
	_check(name_frame.visible, "rename opens the name entry")
	var name_input := menu.get_node("NameFrame/VBox/NameInput") as LineEdit
	name_input.text = "河畔农场"
	menu.call(&"_on_name_confirmed")
	await process_frame
	_check(String(_save.slot_summary(1).get(&"name", "")) == "河畔农场", "rename rewrites the save name")
	_check(_save.has_save(1), "rename keeps the save file")

	# 删除要按两次：第一次只确认
	menu.call(&"_open_slots", 0)
	await process_frame
	row_one = slot_list.get_child(0) as HBoxContainer
	var delete_button := row_one.get_child(2) as Button
	delete_button.pressed.emit()
	_check(delete_button.text == "确认?", "delete asks for confirmation first")
	_check(FileAccess.file_exists(SLOT_ONE), "first click keeps the save")
	delete_button.pressed.emit()
	_check(not FileAccess.file_exists(SLOT_ONE), "second click deletes the save")
	_check(_save.has_save(2), "deleting slot 1 leaves slot 2 alone")
	# 旧行是 queue_free，等一帧再检查重建后的列表
	await process_frame
	_check((slot_list.get_child(0) as HBoxContainer).get_child_count() == 1, "deleted slot loses its delete button")
	menu.queue_free()
	await process_frame
	_save.delete_all()

	print("[pause] %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_main.queue_free()
	await process_frame
	quit(0 if _failures == 0 else 1)


func _spawn_menu() -> Control:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	return menu
