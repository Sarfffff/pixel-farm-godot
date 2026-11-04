extends Control
## 设置面板：音乐/音效音量、窗口模式。挂在 `Main/UI/SettingsPanel`。
##
## 只改玩家偏好（`AppSettings`），不碰存档；改完立刻生效并写入 `user://settings.cfg`。
## 从暂停菜单进入：打开时把暂停菜单藏起来，返回时再打开，避免两层菜单叠着。

@onready var _music_slider: HSlider = %MusicSlider
@onready var _music_value: Label = %MusicValue
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _sfx_value: Label = %SfxValue
@onready var _window_button: Button = %WindowButton
@onready var _hint: Label = %Hint

## 时间流速按钮在代码里建：面板加一行不用改 .tscn，也不影响已有节点路径
var _time_button: Button


func _ready() -> void:
	# 暂停状态下也要能响应输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_music_slider.value_changed.connect(_on_music_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_window_button.pressed.connect(_on_window_pressed)
	var close_button := get_node_or_null("Frame/VBox/CloseButton") as Button
	if close_button != null:
		close_button.pressed.connect(close)
	_build_time_row()
	_sync_from_settings()


## 在「窗口模式」下面插一行「时间流速：慢/标准/快」，点一下循环切换。
func _build_time_row() -> void:
	var vbox := get_node_or_null("Frame/VBox") as VBoxContainer
	if vbox == null:
		return
	_time_button = Button.new()
	_time_button.name = "TimeSpeedButton"
	# 沿用窗口模式按钮的字体与配色，保持同一套像素 UI
	_time_button.add_theme_font_override("font", _window_button.get_theme_font("font"))
	_time_button.add_theme_font_size_override("font_size", _window_button.get_theme_font_size("font_size"))
	_time_button.add_theme_color_override("font_color", _window_button.get_theme_color("font_color"))
	_time_button.pressed.connect(_on_time_speed_pressed)
	vbox.add_child(_time_button)
	vbox.move_child(_time_button, _window_button.get_index() + 1)
	# 多了一行，面板按内容自适应，避免文字被挤出边框
	_fit_frame.call_deferred()


## 按内容最小尺寸把面板居中撑开（锚点都在中心，偏移取一半即可）。
func _fit_frame() -> void:
	var frame := get_node_or_null("Frame") as Control
	if frame == null:
		return
	var wanted: Vector2 = frame.get_combined_minimum_size()
	wanted.x = maxf(wanted.x, 192.0)
	frame.offset_left = -wanted.x * 0.5
	frame.offset_right = wanted.x * 0.5
	frame.offset_top = -wanted.y * 0.5
	frame.offset_bottom = wanted.y * 0.5


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func set_open(is_open: bool) -> void:
	if is_open:
		_sync_from_settings()
		show()
		_fit_frame()
		_music_slider.grab_focus()
	else:
		close()


func close() -> void:
	if not visible:
		return
	hide()
	# 从暂停菜单进来的，关掉设置后回到暂停菜单（场景树仍处于暂停）。
	var pause := get_node_or_null("../PauseMenu") as Control
	if pause != null and get_tree().paused and pause.has_method(&"open"):
		pause.call(&"open")


func _sync_from_settings() -> void:
	var settings := _app_settings()
	if settings == null:
		return
	_music_slider.set_value_no_signal(float(settings.music_percent))
	_sfx_slider.set_value_no_signal(float(settings.sfx_percent))
	_refresh_labels()


func _refresh_labels() -> void:
	_music_value.text = "%d%%" % int(_music_slider.value)
	_sfx_value.text = "%d%%" % int(_sfx_slider.value)
	_window_button.text = "窗口模式：%s" % ("全屏" if _window_button_pressed() else "窗口")
	if _time_button != null:
		var settings := _app_settings()
		_time_button.text = "时间流速：%s" % (settings.time_speed_label() if settings != null else "标准")


func _window_button_pressed() -> bool:
	var settings := _app_settings()
	return bool(settings.fullscreen) if settings != null else false


func _on_music_changed(value: float) -> void:
	var settings := _app_settings()
	if settings != null:
		settings.set_music_percent(int(value))
	_refresh_labels()


func _on_sfx_changed(value: float) -> void:
	var settings := _app_settings()
	if settings != null:
		settings.set_sfx_percent(int(value))
	_refresh_labels()
	# 调音效时给一声反馈，方便听出当前音量。
	_play_ui_sfx()


func _on_window_pressed() -> void:
	var settings := _app_settings()
	if settings == null:
		return
	settings.set_window_mode(not settings.fullscreen)
	_refresh_labels()
	_hint.text = "已切换到%s" % ("全屏" if settings.fullscreen else "窗口")
	_play_ui_sfx()


func _on_time_speed_pressed() -> void:
	var settings := _app_settings()
	if settings == null:
		return
	var count: int = int(settings.call(&"time_speed_count"))
	settings.call(&"set_time_speed", (int(settings.time_speed) + 1) % maxi(count, 1))
	_refresh_labels()
	_hint.text = "时间流速已改为%s" % settings.time_speed_label()
	_play_ui_sfx()


func _play_ui_sfx() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.call(&"play_sfx", &"ui")


func _app_settings() -> Node:
	return get_node_or_null("/root/AppSettings")
