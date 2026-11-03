extends SceneTree
## 鸡与蛋：游走、每天下蛋、捡蛋、满包保留、存档往返、商店卖价。

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[animals] FAIL: " + message)


func _run() -> void:
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame

	var coop: Node2D = main.get_node_or_null("Farm/World/ChickenCoop") as Node2D
	_check(coop != null, "chicken coop placed in world")
	if coop == null:
		_finish(main)
		return
	_check(coop.has_method(&"egg_count"), "coop exposes egg_count")
	_check((main.get_node_or_null("Farm/World/ChickenCoop/Nest") as Sprite2D) != null, "coop has a nest sprite")

	var chickens := get_nodes_in_group(&"chicken")
	_check(chickens.size() == 2, "two chickens in the yard")

	# 鸡会自己走动
	var first := chickens[0] as Node2D
	var start: Vector2 = first.global_position
	for i in 120:
		await physics_frame
	var moved: float = first.global_position.distance_to(start)
	_check(moved > 2.0, "chicken wanders around (moved %.1f px)" % moved)
	var sprite := first.get_node_or_null("Sprite") as Sprite2D
	_check(sprite != null and sprite.hframes == 4 and sprite.vframes == 2, "chicken sheet sliced 4x2")

	# 睡觉 → 每只鸡一颗蛋
	var time := get_first_node_in_group(&"time")
	_check(time != null, "time system present")
	time.call("sleep")
	await process_frame
	_check(int(coop.call("egg_count")) == 2, "each chicken lays an egg after sleeping")
	_check(get_nodes_in_group(&"egg").size() == 2, "eggs are in the world")

	# 蛋能在存档里往返
	var data: Dictionary = coop.call("to_dict")
	_check((data.get(&"eggs", []) as Array).size() == 2, "save data holds two eggs")
	coop.call("clear_eggs")
	await process_frame
	_check(int(coop.call("egg_count")) == 0, "clear_eggs empties the ground")
	coop.call("from_dict", data)
	await process_frame
	_check(int(coop.call("egg_count")) == 2, "eggs come back from save data")

	# 捡蛋
	var inventory := get_first_node_in_group(&"inventory")
	var player := main.get_node("Farm/World/Player") as Node2D
	var before: int = inventory.count_of(&"egg")
	var eggs := get_nodes_in_group(&"egg")
	var egg: Node2D = eggs[0] as Node2D
	player.global_position = egg.global_position + Vector2(0, 8)
	_check(bool(egg.call("player_in_range", player)), "standing on the egg is in range")
	player.global_position = egg.global_position + Vector2(0, 60)
	_check(not bool(egg.call("player_in_range", player)), "walking away leaves the egg range")
	player.global_position = egg.global_position + Vector2(0, 8)
	egg.call("interact", Vector2i.ZERO)
	await process_frame
	await process_frame
	_check(inventory.count_of(&"egg") == before + 1, "picking an egg adds it to the bag")
	_check(int(coop.call("egg_count")) == 1, "coop forgets the picked egg")

	# 满包时蛋留在地上：先把已有的蛋卖掉腾空，否则蛋会堆进同一种物品的格子
	inventory.remove_item(&"egg", inventory.count_of(&"egg"))
	for i in 40:
		inventory.add_item(&"wood", 99)
	await process_frame
	_check(inventory.add_item(&"wood", 1) > 0, "bag is really full")
	var leftovers: Array[Node2D] = []
	for node in get_nodes_in_group(&"egg"):
		if not (node as Node).is_queued_for_deletion():
			leftovers.append(node as Node2D)
	_check(leftovers.size() == 1, "exactly one egg left on the ground")
	if leftovers.size() == 1:
		var leftover: Node2D = leftovers[0]
		leftover.call("interact", Vector2i.ZERO)
		await process_frame
		_check(
			is_instance_valid(leftover) and not leftover.is_queued_for_deletion(),
			"a full bag leaves the egg on the ground"
		)

	# 蛋能卖
	var sell_price: int = 0
	for item: ItemData in inventory.definitions():
		if item.id == &"egg":
			sell_price = item.sell_price
	_check(sell_price > 0, "egg has a sell price")

	_finish(main)


func _finish(main: Node2D) -> void:
	main.queue_free()
	await process_frame
	print("[animals] chickens, eggs, save round trip; %d failures" % _failures)
	quit(0 if _failures == 0 else 1)
