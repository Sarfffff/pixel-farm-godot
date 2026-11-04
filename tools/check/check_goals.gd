extends SceneTree
## 订单与社区中心：每日订单、交付结算、阶段上缴、种子解锁、存档往返。

var _failures: int = 0
var _main: Node2D


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[goals] FAIL: " + message)


## 打开商店看一眼某一项在不在"买入"列表里。
func _shop_sells(id: StringName) -> bool:
	var shop := _main.get_node_or_null("UI/ShopPanel")
	if shop == null:
		return false
	shop.call("set_open", true)
	var found := false
	for row: Dictionary in shop.get(&"_rows"):
		if StringName(row[&"id"]) == id and bool(row[&"buy"]):
			found = true
	shop.call("set_open", false)
	return found


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self):
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	_main.get_node("Systems/Save").set("autoload_enabled", false)
	root.add_child(_main)
	current_scene = _main
	await process_frame
	await process_frame

	var community := get_first_node_in_group(&"community")
	var orders := get_first_node_in_group(&"orders")
	var inventory := get_first_node_in_group(&"inventory")
	var economy := get_first_node_in_group(&"economy")
	var time := get_first_node_in_group(&"time")

	_check(community != null and orders != null, "community and orders systems present")
	_check(_main.get_node_or_null("Farm/World/OrderBin") != null, "order bin placed in world")
	_check(_main.get_node_or_null("Farm/World/CommunityBuilding") != null, "community building placed in world")
	_check(_main.get_node_or_null("UI/OrderPanel") != null, "order panel exists")
	_check(_main.get_node_or_null("UI/CommunityPanel") != null, "community panel exists")

	# 开局：阶段 0、有一张订单
	_check(int(community.stage) == 0, "community starts at stage 0")
	_check(orders.has_order(), "a daily order exists at start")
	_check(int(orders.required()) >= 3, "order asks for several items")
	_check(int(orders.reward()) > 0, "order has a reward")

	# 阶段 0 时萝卜/小麦种子买不到
	_check(_shop_sells(&"carrot_seeds"), "basic seeds are on sale from the start")
	_check(not _shop_sells(&"turnip_seeds"), "turnip seeds locked at stage 0")
	_check(not _shop_sells(&"wheat_seeds"), "wheat seeds locked at stage 0")

	# 上缴第一阶段
	inventory.add_item(&"wood", 15)
	inventory.add_item(&"fiber", 10)
	var coins_before: int = economy.coins
	_check(community.can_donate(), "stage 1 is ready once materials are in")
	_check(community.donate(), "donating completes stage 1")
	_check(int(community.stage) == 1, "community stage advanced")
	_check(inventory.count_of(&"wood") == 0 and inventory.count_of(&"fiber") == 0, "materials consumed")
	_check(economy.coins == coins_before + 300, "stage reward paid")
	_check(_shop_sells(&"turnip_seeds"), "turnip seeds unlocked after stage 1")
	_check(not _shop_sells(&"wheat_seeds"), "wheat still locked at stage 1")

	# 订单交付
	var order_item := StringName(orders.item_id())
	inventory.add_item(order_item, int(orders.required()))
	var coins_before_order: int = economy.coins
	_check(orders.can_deliver(), "order is ready once stocked")
	_check(orders.deliver(), "order delivers")
	_check(economy.coins == coins_before_order + int(orders.reward()), "order reward paid")
	_check(inventory.count_of(order_item) == 0, "order goods taken away")
	_check(not orders.has_order(), "order marked done for today")

	# 谁都不该在已完成后再交一次
	_check(not orders.deliver(), "a finished order cannot be delivered twice")

	# 睡一觉换新订单
	time.call("sleep")
	await process_frame
	_check(orders.has_order(), "a fresh order appears after sleeping")

	# 存档往返
	var snapshot := {
		&"community": community.to_dict(),
		&"orders": orders.to_dict(),
	}
	community.call("from_dict", {})
	orders.call("from_dict", {})
	await process_frame
	_check(int(community.stage) == 0, "community reset for the round trip")
	community.call("from_dict", snapshot[&"community"])
	orders.call("from_dict", snapshot[&"orders"])
	await process_frame
	_check(int(community.stage) == 1, "community stage survives a save round trip")
	_check(orders.item_id() == StringName(snapshot[&"orders"][&"item"]), "order item survives a save round trip")
	_check(int(orders.required()) == int(snapshot[&"orders"][&"count"]), "order count survives a save round trip")

	# 全部修完
	inventory.add_item(&"carrot", 10)
	inventory.add_item(&"egg", 5)
	_check(community.donate(), "stage 2 can be donated")
	inventory.add_item(&"wheat", 8)
	inventory.add_item(&"stone", 10)
	_check(community.donate(), "stage 3 can be donated")
	_check(community.is_finished(), "community reaches its final stage")
	_check(not community.can_donate(), "a finished community cannot be donated again")

	_main.queue_free()
	await process_frame
	print("[goals] orders, community stages, unlocks; %d failures" % _failures)
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)
