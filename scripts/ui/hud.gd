extends Control
## 右上角金币条：订阅 economy，收入时在数字下方飘一个 "+N"。
##
## 只做显示，不持有金币状态；一切数值以 Economy 节点为准。

const FLOAT_HOLD: float = 0.7
const FLOAT_RISE: float = 8.0

@onready var _amount: Label = %Amount
@onready var _clock: Label = %TimeLabel
@onready var _weather: Label = %WeatherLabel
@onready var _stamina_text: Label = %StaminaText
@onready var _stamina_fill: ColorRect = %Fill
@onready var _bar_back: ColorRect = %BarBack

var _economy: Economy
var _time: Node
var _weather_node: Node
var _stamina: Node
var _float: Label


func _ready() -> void:
	_time = get_tree().get_first_node_in_group(&"time")
	if _time != null:
		_time.time_changed.connect(_on_time_changed)
		_on_time_changed(_time.day, _time.minutes)
	_weather_node = get_tree().get_first_node_in_group(&"weather")
	if _weather_node != null:
		_refresh_weather()
		if _weather_node.has_signal(&"weather_changed"):
			_weather_node.weather_changed.connect(func(_kind: StringName) -> void: _refresh_weather())
	_stamina = get_tree().get_first_node_in_group(&"stamina")
	if _stamina != null:
		_stamina.changed.connect(_on_stamina_changed)
		_on_stamina_changed(int(_stamina.value))
	_economy = get_tree().get_first_node_in_group(&"economy") as Economy
	if _economy == null:
		push_warning("[hud] 未找到 economy 组节点，金币条不会更新")
		_amount.text = "0"
		return
	_economy.changed.connect(_on_coins_changed)
	_economy.coins_gained.connect(_on_coins_gained)
	_on_coins_changed(_economy.coins)


func _refresh_weather() -> void:
	if _weather != null and _weather_node != null:
		_weather.text = String(_weather_node.label())


## 体力条：贴右边缘的竖向小条，从下往上填；低于一半变黄、低于四分之一变红。
func _on_stamina_changed(value: int) -> void:
	_stamina_text.text = str(value)
	var ratio := clampf(float(value) / 100.0, 0.0, 1.0)
	var full: Vector2 = _bar_back.size
	if full.y <= 0.0:
		# 第一帧布局还没算完，先按场景里写死的高度兜底。
		full = Vector2(6, 42)
	_stamina_fill.size = Vector2(full.x, full.y * ratio)
	_stamina_fill.position = Vector2(_bar_back.position.x, _bar_back.position.y + full.y * (1.0 - ratio))
	if ratio >= 0.5:
		_stamina_fill.color = Color(0.55, 0.78, 0.42, 1)
	elif ratio >= 0.25:
		_stamina_fill.color = Color(0.88, 0.74, 0.36, 1)
	else:
		_stamina_fill.color = Color(0.85, 0.42, 0.32, 1)


func _on_time_changed(day: int, minutes: int) -> void:
	var hour: int = (minutes / 60) % 24
	var minute: int = minutes % 60
	_clock.text = "第 %d 天 %02d:%02d" % [day, hour, minute]


func _on_coins_changed(coins: int) -> void:
	_amount.text = str(coins)


func _on_coins_gained(amount: int) -> void:
	if _float == null:
		_float = Label.new()
		_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_float.add_theme_font_override("font", _amount.get_theme_font("font"))
		_float.add_theme_font_size_override("font_size", 7)
		_float.add_theme_color_override("font_color", Color("f0d68c"))
		_float.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06, 0.9))
		_float.add_theme_constant_override("outline_size", 2)
		_float.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(_float)
	_float.text = "+%d" % amount
	_float.position = Vector2(_amount.global_position.x - global_position.x - 4.0, _amount.global_position.y - global_position.y)
	_float.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_float, "position:y", _float.position.y - FLOAT_RISE, 0.1 + FLOAT_HOLD)
	tween.parallel().tween_property(_float, "modulate:a", 0.0, FLOAT_HOLD).set_delay(0.1)
