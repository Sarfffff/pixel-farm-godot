extends CanvasModulate
## 昼夜色调：只暗化世界（CanvasModulate 不影响 UI 的 CanvasLayer）。
##
## 17:00 起逐渐变暗，21:00 达到最深，保持到收工时间。
## 天气色以乘法叠加在昼夜色上：雨天偏蓝、阴天稍闷。

const EVENING_START: int = 17 * 60
const FULL_DARK: int = 21 * 60
const NIGHT_COLOR := Color(0.25, 0.32, 0.55)
const MAX_MIX: float = 0.70
## 室内固定暖色：在屋里时不受夜色影响，和室外区分开。
const INDOOR_COLOR := Color(0.97, 0.93, 0.85)
## 季节基色：和昼夜、天气一起做乘法叠加在世界上（不影响 UI）。
const SEASON_TINTS: Dictionary[StringName, Color] = {
	&"spring": Color(1.0, 1.0, 1.0),
	&"summer": Color.WHITE,
	&"autumn": Color.WHITE,
	&"winter": Color.WHITE,
}

var _time: Node
var _weather: Node
var _indoor: bool = false


func _ready() -> void:
	add_to_group(&"day_night_tint")
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


## 进屋/出门时切换：室内常亮，室外按时间与天气变暗。
func set_indoor(indoor: bool) -> void:
	_indoor = indoor
	if _time != null:
		_apply(int(_time.minutes))


func _apply(minutes: int) -> void:
	if _indoor:
		color = INDOOR_COLOR
		return
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
	var season_tint: Color = SEASON_TINTS.get(_season(), Color.WHITE)
	tint = Color(tint.r * season_tint.r, tint.g * season_tint.g, tint.b * season_tint.b, 1.0)
	color = tint


## 当前季节（取不到就按春天，不影响原有昼夜表现）。
func _season() -> StringName:
	if _time != null and _time.has_method(&"season"):
		return StringName(_time.call(&"season"))
	return &"spring"
