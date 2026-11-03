extends Node2D
## 木屋门口：靠近按 E 打开睡前结算，确认后进入第二天。
##
## 与商店同属 interactable 组，玩家按 E 时取最近的一个。

const INTERACT_RADIUS: float = 26.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "[E] 回屋睡觉"


func interact(_cell: Vector2i) -> void:
	var summary := get_tree().current_scene.get_node_or_null("UI/DaySummary")
	if summary != null and summary.has_method(&"set_open"):
		summary.set_open(true)
