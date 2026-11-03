extends Control
## 通用对话框：底部一条对话栏，显示说话人、台词与若干选项。
##
## 具体行为不写死在这里：选中选项后回调 owner 的 `on_dialogue_option(id)`，
## 返回新台词就原地换文字继续聊，返回空就收起对话。

@onready var _speaker: Label = %Speaker
@onready var _text: Label = %Text
@onready var _options: VBoxContainer = %Options
@onready var _overlay: ColorRect = $Overlay

var _owner: Node
var _buttons: Array[Button] = []
var _selected: int = 0


func _ready() -> void:
	_overlay.gui_input.connect(_on_overlay_gui_input)
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_up"):
		_select(_selected - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down"):
		_select(_selected + 1)
		get_viewport().set_input_as_handled()


## options 里每项形如 { &"id": StringName, &"text": String }。
func open_with(speaker: String, text: String, options: Array, owner_node: Node) -> void:
	_owner = owner_node
	_speaker.text = speaker
	_text.text = text
	_build_options(options)
	set_open(true)


func close() -> void:
	set_open(false)


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
	# 打开对话时收起其他面板，避免两个 UI 抢输入锁。
	for panel_name: String in ["InventoryPanel", "ShopPanel", "DaySummary", "HelpPanel", "OrderPanel", "CommunityPanel"]:
		var panel := get_node_or_null("../%s" % panel_name) as Control
		if panel != null and panel.visible:
			panel.call(&"set_open", false)
	_select(0)


func _build_options(options: Array) -> void:
	for child in _options.get_children():
		child.queue_free()
	_buttons.clear()
	for option in options:
		var record: Dictionary = option
		var button := Button.new()
		button.text = String(record.get(&"text", "…"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override("font", _text.get_theme_font("font"))
		button.add_theme_font_size_override("font_size", 7)
		button.add_theme_color_override("font_color", Color(0.94, 0.88, 0.68, 1))
		button.pressed.connect(_choose.bind(StringName(record.get(&"id", ""))))
		_options.add_child(button)
		_buttons.append(button)


func _choose(id: StringName) -> void:
	var next_text := ""
	if _owner != null and _owner.has_method(&"on_dialogue_option"):
		next_text = String(_owner.on_dialogue_option(id))
	if next_text.is_empty():
		# owner 可能已经自己关掉对话去开商店了，重复 close 会把工具栏又放出来。
		if visible:
			close()
		return
	_text.text = next_text


func _select(index: int) -> void:
	if _buttons.is_empty():
		return
	_selected = posmod(index, _buttons.size())
	_buttons[_selected].grab_focus()


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()
