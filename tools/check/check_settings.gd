extends SceneTree
## 设置面板回归：音量换算、AudioManager 联动、设置持久化、面板开关。
## --headless --path . --script res://tools/check/check_settings.gd
##
## 会临时改写 user://settings.cfg，结束时恢复读取前的原值。

const MAIN_SCENE := "res://scenes/main.tscn"

const PREVIEW_PATH := "res://docs/screenshots/settings-panel.png"

var _failures: int = 0
var _original_music: int = 0
var _original_sfx: int = 0
var _original_fullscreen: bool = false
var _original_time_speed: int = 1
var _preview: bool = false


func _init() -> void:
	_preview = "--preview" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[settings] FAIL: " + message)


func _run() -> void:
	var settings := root.get_node_or_null("AppSettings")
	var audio := root.get_node_or_null("AudioManager")
	_check(settings != null, "AppSettings autoload exists")
	_check(audio != null, "AudioManager autoload exists")
	if settings == null or audio == null:
		_finish()
		return

	_original_music = int(settings.music_percent)
	_original_sfx = int(settings.sfx_percent)
	_original_fullscreen = bool(settings.fullscreen)

	# 百分比 -> dB 的边界
	_check(is_equal_approx(settings.percent_to_db(0), -60.0), "0% maps to silence")
	_check(is_equal_approx(settings.percent_to_db(100), 0.0), "100% maps to 0 dB")
	_check(settings.percent_to_db(50) < -5.0 and settings.percent_to_db(50) > -7.0, "50% is about -6 dB")

	# 改音量要立刻作用到播放器
	settings.set_music_percent(50)
	var music_db: float = audio.get(&"_players")[audio.get(&"_active")].volume_db
	_check(absf(music_db - settings.percent_to_db(50)) < 0.5, "music volume applied to active player")
	settings.set_sfx_percent(0)
	_check(is_equal_approx(float(audio.get(&"_sfx_volume_db")), -60.0), "sfx volume reaches silence")

	# 写盘 + 重新读取
	settings.set_music_percent(35)
	settings.set_sfx_percent(45)
	_check(FileAccess.file_exists("user://settings.cfg"), "settings file written")
	settings.music_percent = 0
	settings.sfx_percent = 0
	settings.load_settings()
	_check(int(settings.music_percent) == 35, "music percent survives reload")
	_check(int(settings.sfx_percent) == 45, "sfx percent survives reload")

	# 时间流速：三档映射、写盘重读、与 TimeSystem 联动
	_original_time_speed = int(settings.time_speed)
	settings.set_time_speed(0)
	_check(
		is_equal_approx(float(settings.minutes_per_second()), 10.0 / 7.0),
		"stardew speed maps to 10 min per 7 seconds"
	)
	settings.set_time_speed(2)
	_check(is_equal_approx(float(settings.minutes_per_second()), 4.0), "fast speed maps to 4 min/s")
	settings.set_time_speed(1)
	_check(is_equal_approx(float(settings.minutes_per_second()), 2.0), "standard speed maps to 2 min/s")
	_check(String(settings.time_speed_label()).contains("标准"), "standard speed has a readable label")
	settings.load_settings()
	_check(int(settings.time_speed) == 1, "time speed survives reload")

	# 面板本身：默认隐藏、能开能关
	var main := load(MAIN_SCENE).instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	await process_frame
	var clock := main.get_node_or_null("Systems/Time")
	_check(
		clock != null and is_equal_approx(float(clock.get(&"minutes_per_real_second")), float(settings.minutes_per_second())),
		"time system adopts the configured speed"
	)
	var panel := main.get_node_or_null("UI/SettingsPanel") as Control
	_check(panel != null, "settings panel exists in main scene")
	if panel != null:
		_check(not panel.visible, "settings panel starts hidden")
		_check(panel.process_mode == Node.PROCESS_MODE_ALWAYS, "settings panel keeps input while paused")
		panel.call(&"set_open", true)
		await process_frame
		await process_frame
		_check(panel.visible, "settings panel opens")
		var frame := panel.get_node_or_null("Frame") as Control
		_check(frame != null and frame.size.x >= 150.0 and frame.size.y >= 100.0, "settings frame has a sane size")
		var time_button := panel.get_node_or_null("Frame/VBox/TimeSpeedButton") as Button
		_check(time_button != null, "settings panel has a time speed row")
		if time_button != null:
			var before: int = int(settings.time_speed)
			time_button.pressed.emit()
			_check(int(settings.time_speed) == (before + 1) % 3, "time speed button cycles the setting")
			settings.set_time_speed(_original_time_speed)
		if _preview:
			await _save_preview(panel)
		panel.call(&"close")
		await process_frame
		_check(not panel.visible, "settings panel closes")
	main.free()

	# 恢复原值，避免污染玩家设置
	settings.set_music_percent(_original_music)
	settings.set_sfx_percent(_original_sfx)
	settings.set_window_mode(_original_fullscreen)
	settings.set_time_speed(_original_time_speed)
	_finish()


## 有窗口运行时额外渲染一张设置面板截图，便于人工核对版式。
func _save_preview(panel: Control) -> void:
	panel.call(&"set_open", true)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null:
		push_warning("[settings] 无法获取视口图像，跳过预览")
		return
	var err := image.save_png(PREVIEW_PATH)
	if err == OK:
		print("[settings] preview -> %s" % PREVIEW_PATH)
	else:
		push_warning("[settings] 预览写入失败：%d" % err)


func _finish() -> void:
	if _failures == 0:
		print("[settings] PASS")
	else:
		printerr("[settings] FAIL，共 %d 项" % _failures)
	quit(0 if _failures == 0 else 1)
