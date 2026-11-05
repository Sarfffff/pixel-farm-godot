extends "res://scripts/ui/common/modal_panel.gd"
## 被动View：只渲染Presenter数据并发出休息意图，不推进日期、扣款或保存。

signal sleep_requested

@onready var _title: Label = %Title
@onready var _lines: Label = %Lines
@onready var _sleep_button: Button = %SleepButton
@onready var _overlay: ColorRect = $Overlay
var summary_data: Callable


func _ready() -> void:
	_overlay.gui_input.connect(_on_overlay_gui_input)
	_sleep_button.pressed.connect(_sleep)
	hide()


func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed(&"ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_sleep()
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	_set_modal_open(open)
	if open: _refresh()


func _refresh() -> void:
	if summary_data.is_valid(): render(summary_data.call())


func render(data: Dictionary) -> void:
	_title.text = String(data.get("title", ""))
	_lines.text = String(data.get("lines", ""))
	_sleep_button.text = String(data.get("button", ""))


## 保留既有按钮/检查入口，只发送意图，控制器拥有整个休息流程。
func _sleep() -> void:
	sleep_requested.emit()


func _on_overlay_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		set_open(false)
