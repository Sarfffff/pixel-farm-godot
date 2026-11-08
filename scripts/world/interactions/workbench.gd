extends Node2D
## 固定农舍木桌的交互适配，没有第二套库存或可移动设备状态。

var open_workbench: Callable
var is_unlocked: Callable


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= 30.0


func hint() -> String:
	return "[F] 种子工作台" if is_unlocked.is_valid() and bool(is_unlocked.call()) else "[F] 木桌 · 第一章完成后开放工作台"


func interact(_cell: Vector2i) -> void:
	if open_workbench.is_valid(): open_workbench.call()


func _exit_tree() -> void:
	open_workbench = Callable()
	is_unlocked = Callable()
