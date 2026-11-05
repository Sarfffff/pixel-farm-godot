extends Sprite2D
## 地上的鸡蛋：靠近按 F 捡进背包；背包满了就留在地上，不会凭空消失。

const INTERACT_RADIUS: float = 20.0

## 由鸡窝在生成时写入，捡走时通知它把这一颗从存档列表里划掉。
var coop: Node = null


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"egg")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "按 F 捡起鸡蛋"


func interact(_cell: Vector2i) -> void:
	var inventory := get_tree().get_first_node_in_group(&"inventory")
	if inventory == null or not inventory.has_method(&"add_item"):
		return
	if inventory.add_item(&"egg", 1) > 0:
		_toast("背包满了，先腾一格")
		return
	if coop != null and coop.has_method(&"forget_egg"):
		coop.forget_egg(self)
	queue_free()


func _toast(message: String) -> void:
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and toast.has_method(&"show_message"):
		toast.show_message(message)
