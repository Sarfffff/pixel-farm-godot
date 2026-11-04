extends Control
## 标题界面：继续游戏（先选存档）/ 新游戏（先选槽位）/ 退出。
##
## 「继续」列出三个槽位的信息让玩家挑；「新游戏」也走同一个槽位列表，
## 选中已有存档的槽位等于覆盖它。

enum Mode { CONTINUE, NEW }

const GAME_SCENE: String = "res://scenes/main.tscn"

@onready var _main_frame: PanelContainer = %MainFrame
@onready var _slot_frame: PanelContainer = %SlotFrame
@onready var _slot_title: Label = %SlotTitle
@onready var _slot_list: VBoxContainer = %SlotList
@onready var _name_frame: PanelContainer = %NameFrame
@onready var _name_input: LineEdit = %NameInput
@onready var _name_confirm: Button = %NameConfirm
@onready var _name_back: Button = %NameBack
@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewButton
@onready var _quit_button: Button = %QuitButton
@onready var _back_button: Button = %BackButton
@onready var _save: Node = $Save

var _mode: int = Mode.CONTINUE
## 等待二次确认的删除槽位；0 表示没有待确认的删除。
var _pending_delete: int = 0
var _delete_buttons: Dictionary = {}
## 新游戏时已经选好、但还没起名的槽位。
var _pending_slot: int = 1
## 命名面板当前是在给已有存档改名，而不是新开局。
var _renaming: bool = false


func _ready() -> void:
	_continue_button.disabled = not _save.any_save()
	_continue_button.pressed.connect(_open_slots.bind(Mode.CONTINUE))
	_new_button.pressed.connect(_open_slots.bind(Mode.NEW))
	_quit_button.pressed.connect(_on_quit_pressed)
	_back_button.pressed.connect(_close_slots)
	_name_confirm.pressed.connect(_on_name_confirmed)
	_name_back.pressed.connect(_close_name_entry)
	_name_input.text_submitted.connect(func(_text: String) -> void: _on_name_confirmed())
	_slot_frame.visible = false
	_name_frame.visible = false
	(_continue_button if not _continue_button.disabled else _new_button).grab_focus()
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call(&"play_music", &"menu")


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _name_frame.visible:
		_close_name_entry()
		get_viewport().set_input_as_handled()
	elif _slot_frame.visible:
		_close_slots()
		get_viewport().set_input_as_handled()


func _open_slots(mode: int) -> void:
	_mode = mode
	_main_frame.visible = false
	_slot_frame.visible = true
	_slot_title.text = "继续哪个存档？" if mode == Mode.CONTINUE else "存到哪个槽位？"
	_rebuild_slots()


func _close_slots() -> void:
	_slot_frame.visible = false
	_main_frame.visible = true
	# 可能刚删完存档，回到主面板时重新判断「继续」是否还能点。
	_continue_button.disabled = not _save.any_save()
	(_continue_button if not _continue_button.disabled else _new_button).grab_focus()


func _rebuild_slots() -> void:
	for child in _slot_list.get_children():
		child.queue_free()
	_delete_buttons.clear()
	_pending_delete = 0
	var first_enabled: Button
	for slot in range(1, _save.SLOT_COUNT + 1):
		var summary: Dictionary = _save.slot_summary(slot)
		var exists: bool = bool(summary.get(&"exists", false))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)

		var button := Button.new()
		button.text = _slot_text(slot, summary, exists)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# 继续模式不能选空槽位；新游戏模式任意槽位都能点（有档即覆盖）。
		button.disabled = _mode == Mode.CONTINUE and (not exists or not bool(summary.get("compatible", true)))
		button.pressed.connect(_on_slot_pressed.bind(slot))
		_style_button(button)
		row.add_child(button)

		# 空槽位没有改名/删除入口，避免出现"操作空存档"这种多余按钮。
		if exists:
			var rename_button := Button.new()
			rename_button.text = "改名"
			rename_button.pressed.connect(_on_rename_pressed.bind(slot))
			_style_button(rename_button)
			row.add_child(rename_button)

			var delete_button := Button.new()
			delete_button.text = "删除"
			delete_button.pressed.connect(_on_delete_pressed.bind(slot))
			_style_button(delete_button)
			row.add_child(delete_button)
			_delete_buttons[slot] = delete_button

		_slot_list.add_child(row)
		if first_enabled == null and not button.disabled:
			first_enabled = button
	if first_enabled != null:
		first_enabled.grab_focus()
	else:
		_back_button.grab_focus()


func _style_button(button: Button) -> void:
	button.add_theme_font_override("font", _slot_title.get_theme_font("font"))
	button.add_theme_font_size_override("font_size", 7)
	button.add_theme_color_override("font_color", Color("514c40"))
	# 槽位按钮是两行文本，左对齐比居中对齐更好读。
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT


## 删除要按两次：第一次把按钮变成「确认?」，再点才真的删，防止误触。
func _on_delete_pressed(slot: int) -> void:
	if _pending_delete != slot:
		_pending_delete = slot
		var button := _delete_buttons.get(slot) as Button
		if button != null:
			button.text = "确认?"
			button.grab_focus()
		return
	_save.delete_save(slot)
	_rebuild_slots()
	_slot_title.text = "已删除存档 %d" % slot


## 两行：第一行是槽位 + 农场名，第二行是进度与保存时间。
func _slot_text(slot: int, summary: Dictionary, exists: bool) -> String:
	if not exists:
		return "存档 %d · 空槽位" % slot
	var farm_name := String(summary.get(&"name", "未命名农场"))
	var day: int = int(summary.get(&"day", 1))
	var coins: int = int(summary.get(&"coins", 0))
	var saved_at: int = int(summary.get(&"saved_at", 0))
	var title := "存档 %d · %s" % [slot, farm_name]
	if _mode == Mode.NEW:
		title += "（将覆盖）"
	return "%s\n第 %d 天 · %d 金币 · %s" % [title, day, coins, _format_time(saved_at)]


func _format_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "未知时间"
	var offset: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix_time + offset)
	return "%02d-%02d %02d:%02d" % [int(d.get("month", 1)), int(d.get("day", 1)), int(d.get("hour", 0)), int(d.get("minute", 0))]


func _on_slot_pressed(slot: int) -> void:
	# 新游戏先起名，确认后才清档进游戏；继续则直接用这个槽位。
	if _mode == Mode.NEW:
		_pending_slot = slot
		_slot_frame.visible = false
		_name_frame.visible = true
		# 默认名不要和槽位号重复，玩家直接回车也有个体面的名字。
		_name_input.text = "我的农场" if slot == 1 else "我的农场 %d" % slot
		_name_input.grab_focus()
		_name_input.select_all()
		return
	_save.use_slot(slot)
	get_tree().change_scene_to_file(GAME_SCENE)


## 已有的存档改个名字：只重写 name 字段，不动进度。
func _on_rename_pressed(slot: int) -> void:
	_renaming = true
	_pending_slot = slot
	var summary: Dictionary = _save.slot_summary(slot)
	_slot_frame.visible = false
	_name_frame.visible = true
	_name_input.text = String(summary.get(&"name", "我的农场"))
	_name_input.grab_focus()
	_name_input.select_all()


func _close_name_entry() -> void:
	_renaming = false
	_name_frame.visible = false
	_slot_frame.visible = true
	_rebuild_slots()


## 确认名字：空名字退回默认「存档 N」，然后清档并用这个槽位开局。
func _on_name_confirmed() -> void:
	var farm_name := _name_input.text.strip_edges()
	if farm_name.is_empty():
		farm_name = "我的农场" if _pending_slot == 1 else "我的农场 %d" % _pending_slot
	farm_name = farm_name.left(16)
	if _renaming:
		_renaming = false
		_save.rename_save(_pending_slot, farm_name)
		_name_frame.visible = false
		_slot_frame.visible = true
		_rebuild_slots()
		return
	Engine.set_meta("pending_save_name", farm_name)
	_save.delete_save(_pending_slot)
	_save.use_slot(_pending_slot)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	preload("res://scripts/platform/app_lifecycle.gd").quit(get_tree())
