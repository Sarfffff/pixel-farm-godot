extends Node
## 农场 BGM：白天 / 入夜自动换曲（挂在 `Main/Systems/BGM`）。
##
## 与 `day_night_tint.gd` 共用同一套时间口径：17:00 起画面开始变暗，
## 音乐也在这里切到夜晚曲目；睡醒后时间回到 06:00，自动切回白天曲目。
##
## 用 `get_node_or_null("/root/AudioManager")` 取单例而不是直接写标识符：
## 无头工具脚本可能在 autoload 注册前就加载场景，写死标识符会编译失败。

const EVENING_START: int = 17 * 60
const DAY_TRACK: StringName = &"farm_day"
const NIGHT_TRACK: StringName = &"farm_night"

var _audio: Node
var _time: Node


func _ready() -> void:
	_audio = get_node_or_null("/root/AudioManager")
	_time = get_tree().get_first_node_in_group(&"time")

	if _audio != null:
		_audio.call(&"play_music", DAY_TRACK)
	else:
		push_warning("[bgm_controller] 未找到 AudioManager 单例，背景音乐不可用")
	if _time == null:
		push_warning("[bgm_controller] 未找到 time 组节点，音乐固定为白天曲目")
		return
	_time.time_changed.connect(_on_time_changed)
	_on_time_changed(_time.day, _time.minutes)


func _on_time_changed(_day: int, minutes: int) -> void:
	if _audio == null:
		return
	_audio.call(&"play_music", NIGHT_TRACK if minutes >= EVENING_START else DAY_TRACK)
