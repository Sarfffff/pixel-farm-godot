extends Node
## 玩家设置（autoload：`AppSettings`）：音乐/音效音量、窗口模式，持久化到 `user://settings.cfg`。
##
## 只存"玩家偏好"，不写进存档：换存档槽位时设置保持不变。
## 音量对外用 0–100 的百分比，内部换算成 dB：
##   0%   → 静音（-60 dB）
##   100% → 0 dB（原始响度）
##
## 用法：
##   AppSettings.set_music_percent(60)
##   AppSettings.set_window_mode(true)   # true = 全屏

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION_AUDIO: String = "audio"
const SECTION_DISPLAY: String = "display"
const SECTION_GAME: String = "game"

## 时间流速：每现实秒推进多少游戏分钟。06:00→02:00 共 1200 分钟。
##   1.5 → 一天约 13 分钟（接近星露谷的节奏）
##   2.0 → 一天约 10 分钟（默认）
##   4.0 → 一天约 5 分钟（旧行为）
const TIME_SPEEDS: Array[float] = [1.5, 2.0, 4.0]
const TIME_SPEED_NAMES: Array[String] = ["慢", "标准", "快"]
const DEFAULT_TIME_SPEED: int = 1
## 窗口标题。项目名保持 `My_ai_Game`（改了会换掉 user:// 目录，老存档直接失联），
## 正式名称只在窗口标题和导出产品名上体现。
const PRODUCT_TITLE: String = "Pixel Farm · 像素农场"

const DEFAULT_MUSIC_PERCENT: int = 70
const DEFAULT_SFX_PERCENT: int = 80
const SILENT_DB: float = -60.0

var music_percent: int = DEFAULT_MUSIC_PERCENT
var sfx_percent: int = DEFAULT_SFX_PERCENT
var fullscreen: bool = false
## TIME_SPEEDS 的下标
var time_speed: int = DEFAULT_TIME_SPEED


func _ready() -> void:
	# AudioManager 在同级 autoload 且注册在前，这里可以直接调用。
	load_settings()
	# 引擎在启动后还会按项目名刷一次标题，所以要延到首帧之后再改。
	_apply_window_title.call_deferred()


## 窗口标题与项目名解耦：项目名关系到 user:// 路径，不能动。
func _apply_window_title() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_title(PRODUCT_TITLE)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		music_percent = clampi(int(config.get_value(SECTION_AUDIO, "music", DEFAULT_MUSIC_PERCENT)), 0, 100)
		sfx_percent = clampi(int(config.get_value(SECTION_AUDIO, "sfx", DEFAULT_SFX_PERCENT)), 0, 100)
		fullscreen = bool(config.get_value(SECTION_DISPLAY, "fullscreen", false))
		time_speed = clampi(int(config.get_value(SECTION_GAME, "time_speed", DEFAULT_TIME_SPEED)), 0, TIME_SPEEDS.size() - 1)
	_apply_audio()
	apply_window_mode()
	_apply_time_speed()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION_AUDIO, "music", music_percent)
	config.set_value(SECTION_AUDIO, "sfx", sfx_percent)
	config.set_value(SECTION_DISPLAY, "fullscreen", fullscreen)
	config.set_value(SECTION_GAME, "time_speed", time_speed)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("[app_settings] 无法写入 %s（错误码 %d）" % [SETTINGS_PATH, err])


func set_music_percent(value: int) -> void:
	music_percent = clampi(value, 0, 100)
	_apply_audio()
	save_settings()


func set_sfx_percent(value: int) -> void:
	sfx_percent = clampi(value, 0, 100)
	_apply_audio()
	save_settings()


func set_window_mode(is_fullscreen: bool) -> void:
	fullscreen = is_fullscreen
	apply_window_mode()
	save_settings()


## 当前时间流速（游戏分钟 / 现实秒）
func minutes_per_second() -> float:
	return TIME_SPEEDS[clampi(time_speed, 0, TIME_SPEEDS.size() - 1)]


func time_speed_count() -> int:
	return TIME_SPEEDS.size()


func time_speed_label() -> String:
	var index: int = clampi(time_speed, 0, TIME_SPEED_NAMES.size() - 1)
	return "%s（一天约 %d 分钟）" % [TIME_SPEED_NAMES[index], int(round(1200.0 / minutes_per_second() / 60.0))]


func set_time_speed(index: int) -> void:
	time_speed = clampi(index, 0, TIME_SPEEDS.size() - 1)
	_apply_time_speed()
	save_settings()


func _apply_time_speed() -> void:
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null and time.has_method(&"set_minutes_per_second"):
		time.call(&"set_minutes_per_second", minutes_per_second())


## 百分比 -> dB。0 直接给静音值，避免 linear_to_db(0) 得到 -inf。
static func percent_to_db(percent: int) -> float:
	if percent <= 0:
		return SILENT_DB
	return clampf(linear_to_db(float(mini(percent, 100)) / 100.0), SILENT_DB, 6.0)


func _apply_audio() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null:
		return
	audio.call(&"set_music_volume", percent_to_db(music_percent))
	audio.call(&"set_sfx_volume", percent_to_db(sfx_percent))


func apply_window_mode() -> void:
	# headless（自检）没有真实窗口，跳过以免报错。
	if DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)
