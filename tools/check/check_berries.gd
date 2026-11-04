extends SceneTree
## 野浆果：随机生成（避开水面与道具）、采果带种、种子可种、幼苗两天后结果、存档往返。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[berries] FAIL: " + message)


## 找一格能种浆果的空草地。
func _find_free_cell(grove: Node) -> Vector2i:
	for y in range(5, 23):
		for x in range(4, 35):
			var cell := Vector2i(x, y)
			if bool(grove.call("can_plant_at", cell)):
				return cell
	return Vector2i(-1, -1)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	_main.get_node("Systems/Save").set(&"autoload_enabled", false)
	root.add_child(_main)
	current_scene = _main
	_main.get_node("Systems/Save").remove_from_group(&"save")
	await process_frame
	await process_frame

	var grove := get_first_node_in_group(&"berry_grove")
	var inventory := get_first_node_in_group(&"inventory")
	var stamina := get_first_node_in_group(&"stamina")
	var time := get_first_node_in_group(&"time")
	_check(grove != null, "berry grove present")
	if grove == null or inventory == null or stamina == null or time == null:
		_finish()
		return

	var bushes: Array = grove.get(&"bushes")
	_check(bushes.size() >= 8, "wild bushes scattered at start (%d)" % bushes.size())

	# 生成的每一丛都要落在合法地形上：不在水里、不压耕地、不贴道具。
	var kinds := {}
	var bounds: Rect2 = grove.get(&"BOUNDS")
	var water := _main.get_node("Farm/Water") as TileMapLayer
	var water_cells := {}
	for cell: Vector2i in water.get_used_cells():
		water_cells[cell] = true
	var bad_water: int = 0
	var bad_bounds: int = 0
	for bush: Node in bushes:
		var pos: Vector2 = (bush as Node2D).global_position
		if not bounds.has_point(pos):
			bad_bounds += 1
		if water_cells.has(Vector2i((pos / 16.0).floor())):
			bad_water += 1
		kinds[String(bush.get(&"kind"))] = true
		_check(bush.is_in_group(&"interactable"), "bush is interactable")
		_check(bool(bush.call(&"is_mature")), "wild bush starts mature")
		var texture: Texture2D = bush.call("visual_texture") as Texture2D
		_check(texture != null and texture.resource_path.ends_with("/ripe.png"), "ripe wild bush renders its pixel sprite")
		_check(texture.get_size() == Vector2(32, 32), "world sprite uses native pixel canvas")
	_check(bad_water == 0, "no bush grows on water (%d)" % bad_water)
	_check(bad_bounds == 0, "every bush sits inside the scatter bounds (%d)" % bad_bounds)
	_check(kinds.size() >= 2, "at least two berry kinds (%d)" % kinds.size())

	# 采野生的：两颗果子 + 一颗种子
	var first: Node = bushes[0]
	var kind := StringName(first.get(&"kind"))
	var seed := StringName(first.call(&"seed_id"))
	_check(String(seed).ends_with("_seeds"), "wild bush maps to a seed item (%s)" % seed)
	_check(inventory.definition(seed) != null, "seed item exists in the item table")
	var fruit_before: int = inventory.count_of(kind)
	var seed_before: int = inventory.count_of(seed)
	stamina.call("from_dict", {&"value": 100})
	first.call("interact", Vector2i.ZERO)
	await process_frame
	_check(inventory.count_of(kind) == fruit_before + 2, "picking gives two berries")
	_check(inventory.count_of(seed) == seed_before + 1, "a wild bush also drops a seed")
	_check(int(stamina.value) == 99, "picking costs one stamina")
	_check(not bool(first.call("has_berries")), "bush becomes bare")
	_check(String(first.call("hint")).contains("天"), "bare hint mentions days")
	_check((first.call("visual_texture") as Texture2D).resource_path.ends_with("/bare.png"), "harvesting immediately switches to bare sprite")
	for id: StringName in [&"wild_blackberry", &"wild_raspberry", &"wild_gooseberry"]:
		var fruit: Texture2D = inventory.definition(id).icon
		var seed_texture: Texture2D = inventory.definition(StringName(String(id) + "_seeds")).icon
		_check(fruit.get_size() == Vector2(16, 16) and seed_texture.get_size() == Vector2(16, 16), "fruit and seed packet fit inventory cells")
		_check(fruit != seed_texture, "seed packet is visually distinct from harvested fruit")

	# 用种子种一丛：先是幼苗，采不了
	var cell := _find_free_cell(grove)
	_check(cell != Vector2i(-1, -1), "found a free grass cell to plant on")
	if cell != Vector2i(-1, -1):
		_check(bool(grove.call("can_plant_at", cell)), "free cell accepts a berry seed")
		var planted_before: int = bushes.size()
		grove.call("plant_at", cell, kind)
		await process_frame
		_check(bushes.size() == planted_before + 1, "planting adds a bush")
		var planted: Node = bushes[bushes.size() - 1]
		_check(not bool(planted.get(&"wild")), "planted bush is not wild")
		_check(not bool(planted.call(&"is_mature")), "planted bush starts as a sprout")
		_check(not bool(planted.call(&"has_berries")), "a sprout has no berries")
		_check(String(planted.call("hint")).contains("幼苗"), "sprout hint says so")
		_check((planted.call("visual_texture") as Texture2D).resource_path.ends_with("/sprout.png"), "planted seed starts with smaller sprout art")
		var fruits_after_plant: int = inventory.count_of(kind)
		planted.call("interact", Vector2i.ZERO)
		await process_frame
		_check(inventory.count_of(kind) == fruits_after_plant, "a sprout cannot be picked")

		# 两天后成株，采完不掉种子（只有野生的才掉）
		time.call("sleep")
		await process_frame
		_check(not bool(planted.call(&"is_mature")), "still a sprout after one day")
		time.call("sleep")
		await process_frame
		_check(bool(planted.call(&"is_mature")), "sprout matures after two days")
		_check(bool(planted.call(&"has_berries")), "mature planted bush has berries")
		_check((planted.call("visual_texture") as Texture2D).resource_path.ends_with("/ripe.png"), "growing overnight refreshes ripe art")
		var seeds_before_pick: int = inventory.count_of(seed)
		planted.call("interact", Vector2i.ZERO)
		await process_frame
		_check(inventory.count_of(seed) == seeds_before_pick, "a planted bush drops no seed")

	# 已开垦的地不能种浆果
	var tiller := get_first_node_in_group(&"farm_tiller")
	var soil: Dictionary = tiller.get(&"_soil_state")
	if not soil.is_empty():
		var tilled: Vector2i = soil.keys()[0]
		_check(not bool(grove.call("can_plant_at", tilled)), "tilled ground refuses berry seeds")

	# 再采一次：两天前采的那丛已经自然恢复，重新采一遍才有"光秃"状态可存
	stamina.call("refill")
	first.call("interact", Vector2i.ZERO)
	await process_frame
	_check(not bool(first.call("has_berries")), "first bush picked right before saving")

	# 存档往返：位置、阶段、野生标记都保留
	var snapshot: Dictionary = grove.call("to_dict")
	_check((snapshot.get(&"bushes", []) as Array).size() == bushes.size(), "save holds one row per bush")
	grove.call("from_dict", snapshot)
	await process_frame
	var restored: Array = grove.get(&"bushes")
	_check(restored.size() == bushes.size(), "grove rebuilds from the save")
	if restored.size() == bushes.size():
		for index in restored.size():
			var before_pos: Vector2 = (bushes[index] as Node2D).global_position
			var after_pos: Vector2 = (restored[index] as Node2D).global_position
			_check(before_pos.is_equal_approx(after_pos), "bush position survives the save (%d)" % index)
	_check(not bool(restored[0].call(&"has_berries")), "picked state survives the save")
	_check((restored[0].call("visual_texture") as Texture2D).resource_path.ends_with("/bare.png"), "loading a picked bush restores its bare art")

	_finish()


func _finish() -> void:
	_main.queue_free()
	root.get_node("AudioManager").stop_music(0.0)
	for audio: Node in root.get_node("AudioManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stream = null
	await create_timer(0.1).timeout
	await process_frame
	print("[berries] random scatter, seeds, planting, save round trip; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
