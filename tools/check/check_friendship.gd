extends SceneTree
## 好感度回归：分档阈值、每天一次聊天、送礼扣物品与喜好加成、存档往返。
## --headless --path . --script res://tools/check/check_friendship.gd

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[friendship] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	var main := load(MAIN_SCENE).instantiate() as Node2D
	main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame

	var friendship := main.get_node_or_null("Systems/Friendship")
	_check(friendship != null, "friendship system exists")
	if friendship == null:
		_finish()
		return

	var gardener := main.get_node_or_null("Farm/World/Gardener") as Sprite2D
	_check(gardener != null, "gardener exists")
	_check(StringName(gardener.get(&"npc_id")) == &"gardener", "gardener has an npc id")

	# 分档：0 陌生 / 20 熟人 / 80 朋友 / 160 好友 / 240 挚友
	friendship.set(&"points", {})
	_check(String(friendship.call(&"level_name", &"gardener")) == "陌生", "starts as 陌生")
	friendship.set(&"points", {&"gardener": 20})
	_check(String(friendship.call(&"level_name", &"gardener")) == "熟人", "20 points is 熟人")
	friendship.set(&"points", {&"gardener": 80})
	_check(String(friendship.call(&"level_name", &"gardener")) == "朋友", "80 points is 朋友")
	friendship.set(&"points", {&"gardener": 240})
	_check(String(friendship.call(&"level_name", &"gardener")) == "挚友", "240 points is 挚友")
	_check(int(friendship.call(&"points_to_next", &"gardener")) == 0, "no next level at the top")

	# 聊天：每天一次
	friendship.set(&"points", {})
	await process_frame
	var player := main.get_node("Farm/World/Player") as CharacterBody2D
	var dialogue := main.get_node("UI/DialoguePanel") as Control
	player.global_position = gardener.global_position + Vector2(0, 14)
	gardener.call("interact", Vector2i.ZERO)
	await process_frame
	_check(dialogue.visible, "talking opens the dialogue")
	_check(int(friendship.call(&"points_of", &"gardener")) == 2, "first talk adds 2 points")
	dialogue.call("close")
	gardener.call("interact", Vector2i.ZERO)
	await process_frame
	_check(int(friendship.call(&"points_of", &"gardener")) == 2, "second talk on the same day adds nothing")
	dialogue.call("close")

	# 跨天可以再聊
	var time := main.get_node("Systems/Time")
	time.call("sleep")
	await process_frame
	gardener.call("interact", Vector2i.ZERO)
	await process_frame
	_check(int(friendship.call(&"points_of", &"gardener")) == 4, "talking again next day adds points")
	dialogue.call("close")

	# 送礼：手持喜欢的物品额外加成，且真的扣掉 1 个
	var inventory := main.get_node("Systems/Inventory")
	inventory.call(&"add_item", &"carrot", 2)
	_check(bool(inventory.call(&"assign_hotbar", 5, &"carrot")), "carrot assigned to hotbar")
	inventory.call(&"select_hotbar", 5)
	_check(StringName(inventory.call(&"active_item")) == &"carrot", "carrot is the active item")
	var before_gift: int = int(friendship.call(&"points_of", &"gardener"))
	var reply := String(gardener.call(&"on_dialogue_option", &"gift"))
	_check(int(inventory.call(&"count_of", &"carrot")) == 1, "gift consumes one item")
	_check(
		int(friendship.call(&"points_of", &"gardener")) == before_gift + 20,
		"liked gift adds 20 points (got %d)" % int(friendship.call(&"points_of", &"gardener"))
	)
	_check(reply.contains("最喜欢"), "liked gift has a happy reply")

	# 不喜欢的物品只加基础分
	inventory.call(&"add_item", &"stone", 1)
	inventory.call(&"assign_hotbar", 6, &"stone")
	inventory.call(&"select_hotbar", 6)
	before_gift = int(friendship.call(&"points_of", &"gardener"))
	gardener.call(&"on_dialogue_option", &"gift")
	_check(
		int(friendship.call(&"points_of", &"gardener")) == before_gift + 10,
		"plain gift adds 10 points"
	)

	# 工具不能当礼物（hoe 默认在快捷位 0）
	inventory.call(&"select_hotbar", 0)
	before_gift = int(friendship.call(&"points_of", &"gardener"))
	gardener.call(&"on_dialogue_option", &"gift")
	_check(int(friendship.call(&"points_of", &"gardener")) == before_gift, "tools cannot be gifted")

	# 存档往返
	var snapshot: Dictionary = friendship.call(&"to_dict")
	friendship.set(&"points", {})
	friendship.call(&"from_dict", snapshot)
	_check(int(friendship.call(&"points_of", &"gardener")) == before_gift, "friendship survives save round-trip")

	main.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("[friendship] PASS")
	else:
		printerr("[friendship] FAIL，共 %d 项" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
