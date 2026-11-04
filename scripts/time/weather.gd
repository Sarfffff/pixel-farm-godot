extends Node
## 天气：每天翻一次，雨天等于帮玩家把所有作物浇了。
##
## 挂在 `Main/Systems/Weather`（组 `weather`）。
## 由每日用例在旧日结算之后、新日事件之前更新天气。

signal weather_changed(kind: StringName)

const SUNNY: StringName = &"sunny"
const CLOUDY: StringName = &"cloudy"
const RAINY: StringName = &"rainy"
## 晴天偏多，雨天隔三差五来一场，够用又不烦人。
const WEIGHTS := {
	SUNNY: 50,
	CLOUDY: 30,
	RAINY: 20,
}

var current: StringName = SUNNY
## 锁定天气后不再按天随机，供调试与回归脚本使用，保证同一天气下可重复验证。
var locked: bool = false
var _last_day: int = 0


func _ready() -> void:
	add_to_group(&"weather")
	var time := get_tree().get_first_node_in_group(&"time")
	if time == null:
		return
	_last_day = int(time.day)


## 只有"日期真的变了"才翻天气，一天之内反复 emit 不会重掷。
func begin_day(day: int) -> void:
	if day == _last_day:
		return
	_last_day = day
	if locked:
		return
	roll()


func roll() -> void:
	if locked:
		return
	current = _pick()
	weather_changed.emit(current)


## 固定天气（下雨会影响作物浇水与生长，回归脚本需要可控的晴天）。
func lock(kind: StringName) -> void:
	locked = true
	current = kind if WEIGHTS.has(kind) else SUNNY
	weather_changed.emit(current)


func unlock() -> void:
	locked = false


func _pick() -> StringName:
	var total: int = 0
	for kind: StringName in WEIGHTS:
		total += int(WEIGHTS[kind])
	var point: int = randi() % maxi(total, 1)
	for kind: StringName in WEIGHTS:
		point -= int(WEIGHTS[kind])
		if point < 0:
			return kind
	return SUNNY


func is_rainy() -> bool:
	return current == RAINY


func label() -> String:
	match current:
		RAINY:
			return "雨"
		CLOUDY:
			return "阴"
		_:
			return "晴"


## HUD 用的一句话说明。
func hint() -> String:
	match current:
		RAINY:
			return "下雨了 · 作物自动浇水"
		CLOUDY:
			return "阴天 · 光照一般"
		_:
			return "晴天 · 记得浇水"


## 天气对画面的额外染色，叠在昼夜色调上。
func tint() -> Color:
	match current:
		RAINY:
			return Color(0.72, 0.78, 0.92)
		CLOUDY:
			return Color(0.88, 0.88, 0.9)
		_:
			return Color(1, 1, 1)


func to_dict() -> Dictionary:
	return {&"kind": String(current)}


func from_dict(data: Dictionary) -> void:
	var kind := StringName(String(data.get(&"kind", "sunny")))
	current = kind if WEIGHTS.has(kind) else SUNNY
	var time := get_tree().get_first_node_in_group(&"time")
	if time != null:
		_last_day = int(time.day)
	weather_changed.emit(current)
