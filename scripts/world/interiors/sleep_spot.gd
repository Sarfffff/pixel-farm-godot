extends Node2D
## 床边：站在这儿按 F 打开睡前结算，确认后黑屏过夜、天亮在床边醒来。
##
## 与门、商店同属 interactable 组，玩家按 F 时取最近的一个。
## 换天由RestService、过场由RestController处理；这里只打开被动结算View。

## 只有贴着床才允许睡：半径收紧到 24px（床宽 2 格，站在床脚/床边刚好够）
const INTERACT_RADIUS: float = 24.0


func _ready() -> void:
	add_to_group(&"interactable")


func player_in_range(player: Node2D) -> bool:
	return player.global_position.distance_to(global_position) <= INTERACT_RADIUS


func hint() -> String:
	return "按 F 上床睡觉"


func interact(_cell: Vector2i) -> void:
	var summary := get_tree().current_scene.get_node_or_null("UI/DaySummary")
	if summary != null and summary.has_method(&"set_open"):
		summary.set_open(true)
