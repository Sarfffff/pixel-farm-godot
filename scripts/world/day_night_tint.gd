extends CanvasModulate
## 昼夜色调：只暗化世界（CanvasModulate 不影响 UI 的 CanvasLayer）。
##
## 17:00 起逐渐变暗，21:00 达到最深，保持到收工时间。
## 天气色以乘法叠加在昼夜色上：雨天偏蓝、阴天稍闷。

const EVENING_START: int = 17 * 60
const FULL_DARK: int = 21 * 60
const NIGHT_COLOR := Color(0.58, 0.62, 0.88)
const MAX_MIX: float = 0.55

var _time: Node
var _weather: Node


func _ready() -> void:
	_time = get_tree().get_first_node_in_group(&"time")
	if _time == null:
		push_warning("[day_night_tint] 未找到 time 组节点，昼夜色调保持白天")
		return
	_weather = get_tree().get_first_node_in_group(&"weather")
	if _weather != null and _weather.has_signal(&"weather_changed"):
		_weather.weather_changed.connect(func(_kind: StringName) -> void: _apply(int(_time.minutes)))
	_time.time_changed.connect(_on_time_changed)
	_apply(int(_time.minutes))


func _on_time_changed(_day: int, minutes: int) -> void:
	_apply(minutes)


func _apply(minutes: int) -> void:
	var mix: float = 0.0
	if minutes >= EVENING_START:
		if minutes >= FULL_DARK:
			mix = MAX_MIX
		else:
			mix = float(minutes - EVENING_START) / float(FULL_DARK - EVENING_START) * MAX_MIX
	var tint: Color = Color.WHITE.lerp(NIGHT_COLOR, mix)
	if _weather != null and _weather.has_method(&"tint"):
		var weather_tint: Color = _weather.tint()
		tint = Color(
			tint.r * weather_tint.r, tint.g * weather_tint.g, tint.b * weather_tint.b, 1.0
		)
	color = tint
