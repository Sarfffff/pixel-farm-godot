extends Node2D
## 田边杂草：靠近 E 清理，每丛两份纤维；满包或没体力时保留。

var patch_id: int = 0
var manager: Node


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"forage_patch")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 19.0


func hint() -> String:
	return "[E] 清理杂草 · 纤维 ×2 · 体力 2"


func interact(_cell: Vector2i) -> void:
	var inventory := get_tree().get_first_node_in_group(&"inventory") as Inventory
	var stamina := get_tree().get_first_node_in_group(&"stamina")
	if inventory == null or not inventory.has_space_for(&"fiber", 2):
		_message("背包已满 · 腾出空间再清理")
		return
	if stamina != null and not stamina.spend(2):
		_message("体力不够 · 回屋睡一觉")
		return
	inventory.add_item(&"fiber", 2)
	manager.remove_patch(patch_id)


func _message(text: String) -> void:
	var toast := get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null:
		toast.show_message(text)


func _draw() -> void:
	draw_rect(Rect2(-7, -1, 14, 3), Color("82984e"))
	for blade: Vector2 in [Vector2(-5, -5), Vector2(-1, -8), Vector2(3, -6), Vector2(5, -4)]:
		draw_rect(Rect2(blade, Vector2(2, -blade.y + 1)), Color("507c46"))
		draw_rect(Rect2(blade + Vector2(-1, -1), Vector2(2, 3)), Color("83ad54"))
	draw_rect(Rect2(-1, -8, 1, 3), Color("c7cd77"))
