extends Control
## 标题界面：继续游戏（先选存档）/ 新游戏（先选槽位）/ 退出。
##
## 「继续」列出三个槽位的信息让玩家挑；「新游戏」也走同一个槽位列表，
## 选中已有存档的槽位等于覆盖它。

enum Mode { CONTINUE, NEW }

const GAME_SCENE: String = "res://scenes/main.tscn"
## 存档卡片的缩略图直接裁标题背景图的局部：没有存档截图也不会空着。
const MENU_BG: Texture2D = preload("res://assets/ui/menu_background.png")
## 三个槽位各取农场不同角落（像素坐标，背景图 640×360）。
const THUMB_REGIONS: Array[Rect2] = [
	Rect2(150, 120, 200, 120),
	Rect2(330, 40, 200, 120),
	Rect2(60, 180, 200, 120),
]

@onready var _main_frame: PanelContainer = %MainFrame
@onready var _slot_frame: PanelContainer = %SlotFrame
@onready var _slot_title: Label = %SlotTitle
@onready var _slot_list: HBoxContainer = %SlotList
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
	# 左侧品牌与菜单常驻，右侧弹出存档卡片
	_slot_frame.visible = true
	_slot_title.text = "选择农场" if mode == Mode.CONTINUE else "新农场放到哪块地？"
	_rebuild_slots()
	# 弹出卡片时把焦点交给第一张可用卡片，键盘也能直接选
	if _slot_list.get_child_count() > 0:
		var first_card := _slot_list.get_child(0) as Control
		var action := first_card.get_node_or_null("VBox/Buttons/Action") as Button
		if action != null and not action.disabled:
			action.grab_focus()


func _close_slots() -> void:
	_slot_frame.visible = false
	# 可能刚删完存档，回到主面板时重新判断「继续」是否还能点。
	_continue_button.disabled = not _save.any_save()
	(_continue_button if not _continue_button.disabled else _new_button).grab_focus()


func _rebuild_slots() -> void:
	for child in _slot_list.get_children():
		child.queue_free()
	_delete_buttons.clear()
	_pending_delete = 0
	var first_action: Button
	for slot in range(1, _save.SLOT_COUNT + 1):
		var summary: Dictionary = _save.slot_summary(slot)
		var exists: bool = bool(summary.get(&"exists", false))
		var card := _make_card(slot, summary, exists)
		_slot_list.add_child(card)
		var action := card.get_node("VBox/Buttons/Action") as Button
		if first_action == null and not action.disabled:
			first_action = action
	if first_action != null:
		first_action.grab_focus()
	else:
		_back_button.grab_focus()


## 一张存档卡：缩略色块 + 农场名 + 进度 + 底部三个按钮。
func _make_card(slot: int, summary: Dictionary, exists: bool) -> PanelContainer:
	var font := _slot_title.get_theme_font("font")
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_style(exists))

	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)

	# 缩略图：有档就裁一块农场实景，空档画个灰底加号
	if exists:
		var preview := TextureRect.new()
		preview.name = "Thumb"
		var atlas := AtlasTexture.new()
		atlas.atlas = MENU_BG
		atlas.region = THUMB_REGIONS[(slot - 1) % THUMB_REGIONS.size()]
		preview.texture = atlas
		preview.custom_minimum_size = Vector2(0, 42)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		box.add_child(preview)
	else:
		var thumb := Panel.new()
		thumb.name = "Thumb"
		thumb.custom_minimum_size = Vector2(0, 42)
		thumb.add_theme_stylebox_override("panel", _thumb_style(slot, false))
		var plus := Label.new()
		plus.text = "＋"
		plus.add_theme_font_override("font", font)
		plus.add_theme_font_size_override("font_size", 12)
		plus.add_theme_color_override("font_color", Color(0.62, 0.61, 0.56))
		plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		thumb.add_child(plus)
		box.add_child(thumb)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = String(summary.get(&"name", "我的农场")) if exists else "空着的第 %d 块" % slot
	name_label.add_theme_font_override("font", font)
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color("3a3327") if exists else Color("8b8676"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	var info := Label.new()
	info.name = "Info"
	if exists:
		info.text = "第 %d 天 · %d 金币\n%s" % [
			int(summary.get(&"day", 1)),
			int(summary.get(&"coins", 0)),
			_format_time(int(summary.get(&"saved_at", 0))),
		]
	else:
		info.text = "一块还没开垦的林地"
	info.add_theme_font_override("font", font)
	info.add_theme_font_size_override("font_size", 6)
	info.add_theme_color_override("font_color", Color("6d6757"))
	box.add_child(info)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 2)
	box.add_child(buttons)

	var action := Button.new()
	action.name = "Action"
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 新游戏模式点有档的卡片是"覆盖"，得说清楚，别让玩家以为能续玩
	action.text = ("覆盖" if _mode == Mode.NEW else "进入") if exists else "新建"
	# 继续模式不能选空档；新游戏模式任意槽位都能点（有档即覆盖）。
	action.disabled = _mode == Mode.CONTINUE and (not exists or not bool(summary.get("compatible", true)))
	action.add_theme_font_override("font", font)
	action.add_theme_font_size_override("font_size", 7)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		action.add_theme_stylebox_override(state, _action_style(exists))
	action.add_theme_color_override("font_color", Color("1d3630") if exists else Color("8b8676"))
	action.pressed.connect(_on_slot_pressed.bind(slot))
	buttons.add_child(action)

	# 空槽位没有改名/删除入口，避免出现"操作空存档"这种多余按钮。
	if exists:
		var rename_button := Button.new()
		rename_button.name = "Rename"
		rename_button.text = "✎"
		rename_button.tooltip_text = "改个名字"
		rename_button.add_theme_font_override("font", font)
		rename_button.add_theme_font_size_override("font_size", 7)
		rename_button.pressed.connect(_on_rename_pressed.bind(slot))
		buttons.add_child(rename_button)

		var delete_button := Button.new()
		delete_button.name = "Delete"
		delete_button.text = "✕"
		delete_button.tooltip_text = "删除存档"
		delete_button.add_theme_font_override("font", font)
		delete_button.add_theme_font_size_override("font_size", 7)
		delete_button.pressed.connect(_on_delete_pressed.bind(slot))
		buttons.add_child(delete_button)
		_delete_buttons[slot] = delete_button
	return card


## 卡片底：有档用纸色，空档更淡。
func _card_style(exists: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.95, 0.89, 1) if exists else Color(0.93, 0.92, 0.87, 1)
	style.border_color = Color(0.78, 0.74, 0.64, 1) if exists else Color(0.85, 0.84, 0.79, 1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5)
	return style


## 缩略图占位：三块地各有色调，空档是浅灰。
func _thumb_style(slot: int, exists: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if not exists:
		style.bg_color = Color(0.88, 0.88, 0.84, 1)
	else:
		var tints: Array[Color] = [Color("8fbf74"), Color("7fb2c9"), Color("c9a878")]
		style.bg_color = tints[(slot - 1) % tints.size()]
	style.set_corner_radius_all(3)
	return style


## 主按钮：有档是浅青胶囊，空档是灰面。
func _action_style(exists: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.62, 0.85, 0.8, 1) if exists else Color(0.86, 0.85, 0.8, 1)
	style.set_corner_radius_all(6)
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


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
