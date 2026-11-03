extends Node2D
## 木屋旁的订单箱：靠近按 E 看今天的订单并交付。
##
## 与商店、睡觉点同属 interactable 组，玩家按 E 时取最近的一个。

const INTERACT_RADIUS: float = 24.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	var orders := get_tree().get_first_node_in_group(&"orders")
	if orders != null and orders.has_method(&"has_order") and not orders.has_order():
		return "按 E 看今日订单（今天已交付）"
	return "按 E 看今日订单"


func interact(_cell: Vector2i) -> void:
	var panel := get_tree().current_scene.get_node_or_null("UI/OrderPanel")
	if panel != null and panel.has_method(&"set_open"):
		panel.set_open(true)
