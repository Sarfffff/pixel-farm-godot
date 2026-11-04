extends Node2D
## 室内的木箱：一个"仓库的第二个入口"。
##
## 复用 FarmActivities 的 24 格储物与面板，不另造一套 UI 与存档字段：
## 屋里的箱子和农场木箱看到的是同一批东西（约定为同一个仓库）。
## 如果以后要做"每个箱子独立一格"，把这里换成自己的 StackStore 即可。

const INTERACT_RADIUS: float = 24.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "[E] 打开木箱"


func interact(_cell: Vector2i) -> void:
	var activities := get_tree().get_first_node_in_group(&"farm_activities")
	if activities == null or not activities.has_method(&"interact_activity"):
		return
	activities.call(&"interact_activity", &"storage", -1)
