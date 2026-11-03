extends Control
## 状态牌与农场手记：订阅游戏系统，统一显示时间、天气、金币、体力和目标。
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
var _float_tween: Tween
var _journal_collapsed: bool = false


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
	$Journal/VBox/Toggle.pressed.connect(_toggle_journal)
	_connect_journal.call_deferred()
	get_viewport().size_changed.connect(_refresh_stamina)
	var camera := get_node_or_null("../../Camera")
	if camera != null:
		camera.zoom_changed.connect(_refresh_camera_hint)
		_refresh_camera_hint(camera._desired_zoom)


func _refresh_camera_hint(value: float) -> void:
	$CameraHint.text = "视野 %d%% · 滚轮缩放 · F11 全屏" % roundi(value / 1.25 * 100.0)


func _refresh_weather() -> void:
	if _weather != null and _weather_node != null:
		_weather.text = String(_weather_node.label())


## 带一像素内边距的横向体力条；低于一半变黄、低于四分之一变红。
func _on_stamina_changed(value: int) -> void:
	_stamina_text.text = "体力 %d/100" % value
	var ratio := clampf(float(value) / 100.0, 0.0, 1.0)
	var full: Vector2 = _bar_back.size
	if full.y <= 0.0:
		# 第一帧布局还没算完，先按场景里写死的高度兜底。
		full = Vector2(81, 4)
	_stamina_fill.size = Vector2(floorf((full.x - 2.0) * ratio), full.y - 2.0)
	_stamina_fill.position = _bar_back.position + Vector2.ONE
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
	if _float_tween != null and _float_tween.is_valid():
		_float_tween.kill()
	_float.position = Vector2(_amount.global_position.x - global_position.x - 4.0, _amount.global_position.y - global_position.y)
	_float.modulate.a = 1.0
	_float_tween = create_tween()
	_float_tween.tween_property(_float, "position:y", _float.position.y - FLOAT_RISE, 0.1 + FLOAT_HOLD)
	_float_tween.parallel().tween_property(_float, "modulate:a", 0.0, FLOAT_HOLD).set_delay(0.1)


func _refresh_stamina() -> void:
	if _stamina != null:
		_on_stamina_changed(int(_stamina.value))


func _connect_journal() -> void:
	for group: StringName in [&"tutorial", &"inventory", &"community"]:
		var system := get_tree().get_first_node_in_group(group)
		if system != null:
			system.changed.connect(_refresh_journal)
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders != null:
		orders.order_changed.connect(_refresh_journal)
	_refresh_journal()
	_refresh_stamina.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		_toggle_journal()
		get_viewport().set_input_as_handled()


func _toggle_journal() -> void:
	_journal_collapsed = not _journal_collapsed
	$Journal/VBox/Body.visible = not _journal_collapsed
	_refresh_journal()
	$Journal.reset_size()


func _refresh_journal() -> void:
	var tutorial := get_tree().get_first_node_in_group(&"tutorial")
	if tutorial != null:
		$Journal/VBox/Toggle.text = "%s  [J] %s" % [tutorial.title(), "+" if _journal_collapsed else "−"]
		$Journal/VBox/Body/GuideHint.text = tutorial.hint()
	var community := get_tree().get_first_node_in_group(&"community")
	if community != null:
		var parts: Array[String] = []
		for row: Dictionary in community.progress():
			parts.append("%s%d/%d" % [row[&"name"], row[&"have"], row[&"need"]])
		$Journal/VBox/Body/CommunityGoal.text = "社区 " + "  ".join(parts) if not community.is_finished() else "社区 · 已全部修复"
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders != null:
		$Journal/VBox/Body/OrderGoal.text = "订单 · %s %d/%d · 余%d天" % [
			String(orders.order.get(&"name", "")), orders.owned(), orders.required(), orders.days_left()
		] if orders.has_order() else "订单已交付 · 明天领取新单"
	$Journal.reset_size()


func set_ui_visible(shown: bool) -> void:
	$Journal.visible = shown
