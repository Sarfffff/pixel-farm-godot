class_name TimeSystem
extends Node
## 游戏内时间：一天从 06:00 开始，02:00 收工；睡觉进入第二天并结算作物。
##
## 加入 time 组，其他系统用 get_first_node_in_group(&"time") 访问。
## 只负责时间与日期，不做存档、不碰界面。

signal time_changed(day: int, minutes: int)
## 新的一天开始（睡觉结算完、日期已 +1），作物在这里统一生长。
signal day_started(day: int)
## 到了收工时间（次日 02:00），由主场景决定弹结算还是直接睡。
signal day_over

## 06:00 起床。
const START_MINUTES: int = 6 * 60
## 26:00 = 次日 02:00，超过就强制收工。
const CLOSE_MINUTES: int = 26 * 60
## 1 现实秒 = 4 游戏分钟：06:00 玩到 02:00 约 5 分钟真实时间。
const MINUTES_PER_REAL_SECOND: float = 4.0

var day: int = 1
var minutes: int = START_MINUTES
## 暂停时置 false，时间与昼夜色调一起停住。
var running: bool = true

var _last_emitted: int = -1
var _closed_today: bool = false
var _minute_fraction: float = 0.0


func _ready() -> void:
	add_to_group(&"time")
	# 耕地脚本在自己的 _ready 里入组，这里延迟一帧再接线，避免依赖节点顺序。
	_connect_farm.call_deferred()


## 新的一天先让耕地结算作物（浇过水的长一阶），再广播给其他系统。
## 用组查找 + 动态调用，不依赖 TimeSystem 这个类名，避免类缓存在外部编辑器里失效。
func _connect_farm() -> void:
	var tiller := get_tree().get_first_node_in_group(&"farm_tiller")
	if tiller != null and tiller.has_method(&"begin_new_day"):
		day_started.connect(func(_day: int) -> void: tiller.begin_new_day())


func _process(delta: float) -> void:
	if not running:
		return
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group(&"player")
		if player != null and player.input_locked:
			return
	var before: int = minutes
	_minute_fraction += maxf(delta, 0.0) * MINUTES_PER_REAL_SECOND
	var elapsed: int = int(floor(_minute_fraction + 0.000001))
	_minute_fraction = maxf(0.0, _minute_fraction - elapsed)
	minutes = mini(minutes + elapsed, CLOSE_MINUTES)
	if minutes != before and minutes != _last_emitted:
		_last_emitted = minutes
		time_changed.emit(day, minutes)
	if minutes >= CLOSE_MINUTES and not _closed_today:
		_closed_today = true
		day_over.emit()


## 睡觉：日期 +1、时间回到 06:00，先广播新一天让作物结算。
func sleep() -> void:
	day += 1
	minutes = START_MINUTES
	reset_clock()
	time_changed.emit(day, minutes)
	day_started.emit(day)


## 睡觉和读档都清掉上一局的小数余量与收工标记。
func reset_clock() -> void:
	_minute_fraction = 0.0
	_last_emitted = -1
	_closed_today = false


func clock_text() -> String:
	var hour: int = (minutes / 60) % 24
	var minute: int = minutes % 60
	return "%02d:%02d" % [hour, minute]


## 是否已经入夜（18:00 之后），供 HUD 与画面色调使用。
func is_evening() -> bool:
	return minutes >= 18 * 60


## 0..1 的夜色强度：18:00 起渐暗，22:00 全黑，凌晨又慢慢回亮。
func darkness() -> float:
	if minutes < 17 * 60 or minutes >= CLOSE_MINUTES:
		return 0.0 if minutes < 17 * 60 else 1.0
	if minutes < 20 * 60:
		return float(minutes - 17 * 60) / float(3 * 60) * 0.65
	return 0.65
