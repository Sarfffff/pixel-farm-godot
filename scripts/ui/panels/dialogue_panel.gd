extends "res://scripts/ui/common/modal_panel.gd"
## 通用对话框：底部一条对话栏，显示说话人、台词与若干选项。
##
## 具体行为不写死在这里：选中选项后回调 owner 的 `on_dialogue_option(id)`，
## 返回新台词就原地换文字继续聊，返回空就收起对话。

@onready var _speaker: Label = %Speaker
@onready var _text: Label = %Text
@onready var _options: VBoxContainer = %Options
@onready var _overlay: ColorRect = $Overlay
@onready var _portrait: TextureRect = %Portrait
const Portraits = preload("res://scripts/presentation/portrait_library.gd")
var portrait_emotion: StringName = &"neutral"

var _owner: Node
var _buttons: Array[Button] = []
var _selected: int = 0
## 多句台词队列（open_lines 使用）
var _lines: Array[String] = []
var _line_index: int = 0
var _pending_options: Array = []


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
	_set_portrait(&"concerned" if text.contains("打烊") else &"neutral")
	_lines.clear()
	_pending_options = []
	_speaker.text = speaker
	_text.text = text
	_build_options(options)
	set_open(true)


## 多句台词：逐句"继续"，最后一句才给出 options（不传就自动给"再见"）。
func open_lines(speaker: String, lines: Array, owner_node: Node, options: Array = []) -> void:
	if lines.is_empty():
		return
	_owner = owner_node
	_set_portrait(&"neutral")
	_lines.clear()
	for line in lines:
		_lines.append(String(line))
	_line_index = 0
	_pending_options = options
	_speaker.text = speaker
	_show_current_line()
	set_open(true)


func _show_current_line() -> void:
	if _lines.is_empty():
		close()
		return
	_text.text = _lines[clampi(_line_index, 0, _lines.size() - 1)]
	var is_last: bool = _line_index >= _lines.size() - 1
	var shown: Array = []
	if not is_last:
		shown = [{&"id": StringName("__next"), &"text": "继续"}]
	elif not _pending_options.is_empty():
		shown = _pending_options
	else:
		shown = [{&"id": StringName("__close"), &"text": "再见"}]
	_build_options(shown)
	_select(0)


func close() -> void:
	set_open(false)


func set_open(open: bool) -> void:
	_set_modal_open(open)
	if not open:
		_lines.clear()
		_line_index = 0
		_pending_options.clear()
		return
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
		button.add_theme_color_override("font_color", Color("514c40"))
		button.pressed.connect(_choose.bind(StringName(record.get(&"id", ""))))
		_options.add_child(button)
		_buttons.append(button)


func _choose(id: StringName) -> void:
	# 多句台词的内部选项，不回调 NPC。
	if id == &"__next":
		_line_index += 1
		_show_current_line()
		return
	if id == &"__close":
		close()
		return
	var next_text := ""
	if _owner != null and _owner.has_method(&"on_dialogue_option"):
		next_text = String(_owner.on_dialogue_option(id))
	if next_text.is_empty():
		# owner 可能已经自己关掉对话去开商店了，重复 close 会把工具栏又放出来。
		if visible:
			close()
		return
	_text.text = next_text
	_set_portrait(&"happy" if id == &"gift" else &"neutral")


func _set_portrait(emotion: StringName) -> void:
	portrait_emotion = emotion
	_portrait.texture = Portraits.for_owner(_owner, emotion)
	_portrait.visible = _portrait.texture != null


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
