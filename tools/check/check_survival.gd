extends SceneTree
## 体力与天气：扣减、拦截、睡醒回满、雨天自动浇水、HUD 联动、存档往返。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[survival] FAIL: " + message)


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	_main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame

	var stamina := get_first_node_in_group(&"stamina")
	var weather := get_first_node_in_group(&"weather")
	var tiller := get_first_node_in_group(&"farm_tiller")
	var time := get_first_node_in_group(&"time")
	var inventory := get_first_node_in_group(&"inventory")

	_check(stamina != null and weather != null, "stamina and weather systems present")
	_check(int(stamina.value) == 100, "stamina starts full")
	_check(time != null and tiller != null, "time and tiller present")

	# HUD 上要有体力与天气
	var hud := _main.get_node_or_null("UI/HUD")
	_check(hud != null, "hud exists")
	var stamina_text: Label = hud.get_node_or_null("%StaminaText") as Label
	var stamina_fill: ColorRect = hud.get_node_or_null("%Fill") as ColorRect
	var bar_back: ColorRect = hud.get_node_or_null("%BarBack") as ColorRect
	var weather_label: Label = hud.get_node_or_null("%WeatherLabel") as Label
	_check(stamina_text != null and stamina_fill != null, "hud shows a stamina bar")
	_check(weather_label != null and not weather_label.text.is_empty(), "hud shows the weather")

	# 扣体力与拒绝
	stamina.call("spend", 30)
	await process_frame
	_check(int(stamina.value) == 70, "spending removes stamina")
	if stamina_text != null:
		_check(String(stamina_text.text).contains("70"), "hud follows the stamina value")
	if stamina_fill != null and bar_back != null:
		_check(
			absf(stamina_fill.size.x - (bar_back.size.x - 2.0) * 0.7) < 1.0,
			"bar width follows the ratio"
		)
	_check(not bool(stamina.call("spend", 500)), "overspending is rejected")
	_check(int(stamina.value) == 70, "a rejected spend changes nothing")

	# 体力见底后锄地被拦住
	stamina.call("from_dict", {&"value": 2})
	await process_frame
	_check(not bool(tiller.call("can_use", &"hoe", Vector2i(22, 6))), "low stamina blocks tilling")
	_check(
		String(tiller.call("interaction_hint", &"hoe")).contains("体力"),
		"hint tells the player to sleep"
	)

	# 睡醒回满
	time.call("sleep")
	await process_frame
	_check(int(stamina.value) == 100, "sleeping refills stamina")

	# 雨天：不浇水也长一阶
	weather.set("current", &"rainy")
	_check(bool(weather.call("is_rainy")), "weather can be rainy")
	_check(weather.call("tint") != Color.WHITE, "rainy weather tints the world")
	inventory.add_item(&"carrot_seeds", 4)
	var rain_cell := Vector2i(20, 7)
	tiller.call("_plant", rain_cell)
	var crops: Dictionary = tiller.get(&"_crops")
	var rain_crop: Node = crops.get(rain_cell)
	_check(rain_crop != null and int(rain_crop.stage) == 0, "crop planted at stage 0")
	tiller.call("begin_new_day")
	await process_frame
	_check(int(rain_crop.stage) == 1, "rain grows the crop without hand watering")

	# 晴天不浇水就不长
	weather.set("current", &"sunny")
	var dry_cell := Vector2i(21, 7)
	tiller.call("_plant", dry_cell)
	crops = tiller.get(&"_crops")
	var dry_crop: Node = crops.get(dry_cell)
	_check(dry_crop != null, "second crop planted")
	tiller.call("begin_new_day")
	await process_frame
	_check(int(dry_crop.stage) == 0, "a dry day without watering does not grow")

	# 存档往返
	var snapshot := {
		&"stamina": stamina.call("to_dict"),
		&"weather": weather.call("to_dict"),
	}
	stamina.call("from_dict", {&"value": 100})
	weather.call("from_dict", {&"kind": "sunny"})
	stamina.call("from_dict", snapshot[&"stamina"])
	weather.call("from_dict", snapshot[&"weather"])
	_check(int(stamina.value) == int(snapshot[&"stamina"][&"value"]), "stamina survives a save round trip")
	_check(
		String(weather.get("current")) == String(snapshot[&"weather"][&"kind"]),
		"weather survives a save round trip"
	)

	_main.queue_free()
	await process_frame
	print("[survival] stamina, weather, rain watering; %d failures" % _failures)
	quit(0 if _failures == 0 else 1)
