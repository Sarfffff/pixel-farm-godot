extends Control
## 暂停菜单：Esc 打开，暂停整个场景树；可继续、保存、返回标题。
##
## 只有在背包/商店/日报都没开的时候才响应 Esc，避免和面板的关闭逻辑打架。

@onready var _buttons: VBoxContainer = %Buttons
@onready var _hint: Label = %Hint
@onready var _subtitle: Label = %Subtitle
@onready var _music_button: Button = %MusicButton
@onready var _sfx_button: Button = %SfxButton

var _items: Array[Button] = []
var _selected: int = 0


func _ready() -> void:
	# 暂停时依然要能响应输入与动画，所以整个菜单走 ALWAYS。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_buttons()
	hide()


func _collect_buttons() -> void:
	for child in _buttons.get_children():
		var button := child as Button
		if button == null:
			continue
		_items.append(button)
		button.pressed.connect(_on_button_pressed.bind(_items.size() - 1))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if visible:
			close()
			get_viewport().set_input_as_handled()
		elif can_pause():
			open()
			get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_up"):
		_select(_selected - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_select(_selected + 1)
		get_viewport().set_input_as_handled()


## 其他面板开着时 Esc 归面板自己处理，不弹暂停。
func can_pause() -> bool:
	for panel: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		if panel is Control and panel.visible:
			return false
	for panel_name: String in ["InventoryPanel", "ShopPanel", "DaySummary", "DialoguePanel", "HelpPanel", "OrderPanel", "CommunityPanel"]:
		var panel := get_node_or_null("../%s" % panel_name) as Control
		if panel != null and panel.visible:
			return false
	return not visible


func open() -> void:
	visible = true
	_hint.text = "Esc 继续游戏"
	_refresh_subtitle()
	_refresh_audio_labels()
	_select(0)
	get_tree().paused = true
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(true)


func close() -> void:
	visible = false
	get_tree().paused = false
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"set_input_locked"):
		player.set_input_locked(false)


func _select(index: int) -> void:
	if _items.is_empty():
		return
	_selected = posmod(index, _items.size())
	_items[_selected].grab_focus()


func _on_button_pressed(index: int) -> void:
	match index:
		0: close()
		1: _save_game()
		2: _back_to_title()
		3: _open_help()
		4: _toggle_music()
		5: _toggle_sfx()


## 音乐开关：关掉后切场景也不会突然响起来（开关状态只影响本次运行）。
func _toggle_music() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	audio.call(&"set_music_enabled", not bool(audio.get(&"music_enabled")))
	_refresh_audio_labels()


func _toggle_sfx() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	var enabled := not bool(audio.get(&"sfx_enabled"))
	audio.call(&"set_sfx_enabled", enabled)
	_refresh_audio_labels()
	if enabled:
		# 打开时给一声反馈，同时验证真的响了。
		audio.call(&"play_sfx", &"ui")


func _refresh_audio_labels() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	var music_on := true
	var sfx_on := true
	if audio != null:
		music_on = bool(audio.get(&"music_enabled"))
		sfx_on = bool(audio.get(&"sfx_enabled"))
	if _music_button != null:
		_music_button.text = "音乐：%s" % ("开" if music_on else "关")
	if _sfx_button != null:
		_sfx_button.text = "音效：%s" % ("开" if sfx_on else "关")


## 帮助面板会顺手把暂停菜单关掉，这里不用再 close 一次。
func _open_help() -> void:
	var help := get_node_or_null("../HelpPanel") as Control
	if help != null and help.has_method(&"set_open"):
		help.call(&"set_open", true)


## 暂停面板最上面的一行：农场名 · 第几天 · 存档槽位，方便确认自己在玩哪个档。
func _refresh_subtitle() -> void:
	var save := get_tree().get_first_node_in_group(&"save")
	var time := get_tree().get_first_node_in_group(&"time")
	var farm_name: String = save.save_name if save != null else "农场"
	var day: int = time.day if time != null else 1
	var slot: int = save.current_slot if save != null else 1
	_subtitle.text = "%s · 第 %d 天 · 存档 %d" % [farm_name, day, slot]


func _save_game() -> void:
	var save := get_tree().get_first_node_in_group(&"save")
	if save == null or not save.has_method(&"save_game"):
		_hint.text = "没有存档系统"
		return
	if save.save_game():
		_hint.text = "已保存到存档 %d" % save.current_slot
	else:
		_hint.text = "保存失败"


func _back_to_title() -> void:
	var save := get_tree().get_first_node_in_group(&"save")
	if save != null and save.has_method(&"save_game"):
		save.save_game()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
