extends SceneTree
## 野浆果采集：落点数量与种类、采集产出、体力消耗、两天恢复、满包保留、存档往返。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[berries] FAIL: " + message)


func _run() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	_main.get_node("Systems/Save").set(&"autoload_enabled", false)
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame

	var grove := get_first_node_in_group(&"berry_grove")
	var inventory := get_first_node_in_group(&"inventory")
	var stamina := get_first_node_in_group(&"stamina")
	var time := get_first_node_in_group(&"time")
	_check(grove != null, "berry grove present")
	if grove == null:
		_finish()
		return
	_check(inventory != null and stamina != null and time != null, "inventory / stamina / time present")
	if inventory == null or stamina == null or time == null:
		_finish()
		return

	var bushes: Dictionary = grove.get(&"bushes")
	_check(bushes.size() == 8, "eight berry bushes (%d)" % bushes.size())
	var kinds := {}
	for slot: int in bushes.keys():
		var bush: Node = bushes[slot]
		_check(bush.is_in_group(&"interactable"), "bush is interactable")
		kinds[String(bush.get(&"kind"))] = true
	_check(kinds.size() == 3, "three berry kinds (%d)" % kinds.size())

	# 有果：采一把
	var first: Node = bushes[0]
	_check(bool(first.call("has_berries")), "bush starts ripe")
	_check(String(first.call("hint")).contains("采"), "ripe hint invites picking")
	var kind := StringName(first.get(&"kind"))
	var before: int = inventory.count_of(kind)
	stamina.call("from_dict", {&"value": 100})
	first.call("interact", Vector2i.ZERO)
	await process_frame
	_check(inventory.count_of(kind) == before + 2, "picking gives two berries")
	_check(int(stamina.value) == 99, "picking costs one stamina")
	_check(not bool(first.call("has_berries")), "bush becomes bare")
	_check(String(first.call("hint")).contains("天"), "bare hint mentions days")

	# 光秃秃的时候再按不给东西
	var after: int = inventory.count_of(kind)
	first.call("interact", Vector2i.ZERO)
	await process_frame
	_check(inventory.count_of(kind) == after, "a bare bush gives nothing")

	# 两天后重新结果
	time.call("sleep")
	await process_frame
	_check(not bool(first.call("has_berries")), "still bare the next day")
	time.call("sleep")
	await process_frame
	_check(bool(first.call("has_berries")), "bush regrows two days later")

	# 满包：不采、不扣体力
	var second: Node = bushes[1]
	var kind2 := StringName(second.get(&"kind"))
	for i in 40:
		inventory.add_item(&"wood", 99)
	stamina.call("refill")
	var stamina_before: int = int(stamina.value)
	second.call("interact", Vector2i.ZERO)
	await process_frame
	_check(bool(second.call("has_berries")), "a full bag keeps the berries")
	_check(int(stamina.value) == stamina_before, "a full bag costs no stamina")
	_check(inventory.count_of(kind2) == 0, "nothing sneaks into a full bag")

	# 存档往返：采过的保持光秃，没采的保持有果
	first.call("interact", Vector2i.ZERO)
	await process_frame
	_check(not bool(first.call("has_berries")), "first bush picked again")
	var snapshot: Dictionary = grove.call("to_dict")
	_check((snapshot.get(&"bushes", []) as Array).size() == 8, "save holds eight rows")
	grove.call("from_dict", snapshot)
	await process_frame
	var restored: Dictionary = grove.get(&"bushes")
	_check(restored.size() == 8, "grove rebuilds from the save")
	_check(not bool(restored[0].call("has_berries")), "picked state survives the save")
	_check(bool(restored[1].call("has_berries")), "unpicked state survives the save")

	_finish()


func _finish() -> void:
	_main.queue_free()
	await process_frame
	print("[berries] forage bushes, regrow, save round trip; %d failures" % _failures)
	quit(0 if _failures == 0 else 1)
